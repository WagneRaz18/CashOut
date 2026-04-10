import Foundation
import CloudKit
@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CloudSharingService")

@MainActor
protocol CloudSharingServiceProtocol {
    var isShared: Bool { get }
    var isShareOwner: Bool { get }
    var partnerName: String? { get }
    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer)
    func checkSharingStatus() async
    func persistUpdatedShare(_ share: CKShare)
    func prepareObjectForSharedSave(_ object: NSManagedObject)
    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws
    func resetState()
    func cancelShare() async throws
}

@MainActor
@Observable
final class CloudSharingService: CloudSharingServiceProtocol {
    static let shared = CloudSharingService()

    var isShared: Bool = false
    var partnerName: String? = nil

    var isShareOwner: Bool = false

    @ObservationIgnored private var currentShare: CKShare? = nil

    /// Tracks a recently-canceled share's recordName so `checkSharingStatus()` and
    /// `createShare()` skip the stale CKShare that remains in the local Core Data
    /// mirror until NSPersistentCloudKitContainer processes the CloudKit deletion.
    /// Persisted to UserDefaults to survive app termination during the sync window.
    @ObservationIgnored private var canceledShareRecordName: String? = nil
    @ObservationIgnored private var canceledShareTimestamp: Date? = nil
    private static let canceledShareKey = "CashOut.canceledShareRecordName"
    private static let canceledShareTimestampKey = "CashOut.canceledShareTimestamp"
    /// How long to suppress a stale share after cancellation (seconds).
    /// The mirror typically catches up within 5–15s on a live connection.
    private static let canceledShareTTL: TimeInterval = 120

    /// Record name of the share whose pre-invite expenses were already back-filled
    /// into the shared zone. Persisted to UserDefaults so we don't re-run the
    /// back-fill on every `checkSharingStatus` debounce or app relaunch. Resets
    /// when a different share is created (new invite after cancel).
    @ObservationIgnored private var backfilledShareRecordName: String? = nil
    @ObservationIgnored private var backfillTask: Task<Void, Never>? = nil
    private static let backfilledShareKey = "CashOut.backfilledShareRecordName"

    private let persistenceController: PersistenceController
    private static let containerIdentifier = "iCloud.com.wagneraz.CashOut"

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
        // Restore cancellation sentinel from UserDefaults (survives app termination)
        if let name = UserDefaults.standard.string(forKey: Self.canceledShareKey),
           let ts = UserDefaults.standard.object(forKey: Self.canceledShareTimestampKey) as? Date,
           Date().timeIntervalSince(ts) < Self.canceledShareTTL {
            canceledShareRecordName = name
            canceledShareTimestamp = ts
            logger.debug("CloudSharingService.init — restored canceledShareRecordName=\(name)")
        } else {
            clearCanceledShareSentinel()
        }
        backfilledShareRecordName = UserDefaults.standard.string(forKey: Self.backfilledShareKey)
        logger.debug("CloudSharingService.init")
    }

    /// Creates or reuses a CKShare for the given managed objects.
    /// - Important: Callers must pass deduplicated objects — `container.share()` sends
    ///   all objects to CloudKit. Display-layer dedup (e.g., `fetchCategories`) does NOT
    ///   protect this path; duplicate managed objects will create redundant CKRecords.
    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer) {
        logger.info("createShare: \(objects.count) objects")
        assert(Set(objects.map(\.objectID)).count == objects.count,
               "createShare: duplicate objectIDs passed — caller must deduplicate")
        guard !objects.isEmpty else {
            logger.error("createShare: no objects provided")
            throw NSError(
                domain: "CloudSharingService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot create share with no objects — at least one managed object is required"]
            )
        }

        guard FileManager.default.ubiquityIdentityToken != nil else {
            logger.error("createShare: no iCloud account")
            throw NSError(
                domain: "CloudSharingService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to iCloud in Settings to invite a partner."]
            )
        }

        // Re-validate cached share before reuse (may have been revoked)
        if let existingShare = currentShare {
            logger.debug("createShare: validating cached share")

            // Sentinel check FIRST — must block regardless of network state
            if isRecentlyCanceled(recordName: existingShare.recordID.recordName) {
                logger.info("createShare: cached share was recently canceled — creating new")
                currentShare = nil
            } else {
                // Owner-created shares always live in the private store.
                // Participants never call createShare() — this is always the owner path.
                let validationStore = persistenceController.privatePersistentStore
                if let store = validationStore {
                    do {
                        let freshShares = try persistenceController.container.fetchShares(in: store)
                        if freshShares.contains(where: { $0.recordID == existingShare.recordID }) {
                            logger.info("createShare: reusing existing valid share")
                            return (existingShare, CKContainer(identifier: Self.containerIdentifier))
                        } else {
                            // Share not found in store — revoked or deleted, create new
                            logger.info("createShare: cached share no longer valid — creating new")
                            currentShare = nil
                        }
                    } catch {
                        // Transient error (network, etc.) — keep cached share to avoid duplicate creation
                        logger.error("createShare: fetchShares validation failed — \(error.localizedDescription), reusing cached")
                        return (existingShare, CKContainer(identifier: Self.containerIdentifier))
                    }
                }
            }
        }

        logger.info("createShare: creating new CloudKit share")
        let (_, share, _) = try await persistenceController.container.share(objects, to: nil)
        clearCanceledShareSentinel()
        // Fresh share — reset the back-fill marker so pre-invite expenses get
        // moved into the new shared zone the next time checkSharingStatus runs.
        clearBackfillMarker()
        currentShare = share
        share[CKShare.SystemFieldKey.title] = "CashOut Household"
        logger.info("createShare: new share created successfully")
        return (share, CKContainer(identifier: Self.containerIdentifier))
    }

    func checkSharingStatus() async {
        logger.info("checkSharingStatus: checking stores for shares")
        let checkStart = CFAbsoluteTimeGetCurrent()

        if let share = fetchActiveShare(from: persistenceController.privatePersistentStore, label: "private") {
            isShared = true
            isShareOwner = true
            currentShare = share
            extractPartnerInfo(from: share)
            // Back-fill pre-invite expenses into the shared zone exactly once per
            // unique share. Guarded by recordName comparison so debounce storms
            // and app relaunches don't re-run the work, but a fresh share after
            // a cancel (different recordName) does trigger a new back-fill.
            scheduleBackfillIfNeeded(for: share)
            let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
            logger.info("checkSharingStatus: found share in private store (owner) — \(elapsed, format: .fixed(precision: 1))ms")
            return
        }

        if let share = fetchActiveShare(from: persistenceController.sharedPersistentStore, label: "shared") {
            isShared = true
            isShareOwner = false
            currentShare = share
            extractPartnerInfo(from: share)
            let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
            logger.info("checkSharingStatus: found share in shared store (participant) — \(elapsed, format: .fixed(precision: 1))ms")
            return
        }

        // No shares found (or only stale canceled shares) — solo mode
        guard persistenceController.privatePersistentStore != nil ||
              persistenceController.sharedPersistentStore != nil else {
            logger.warning("checkSharingStatus: both stores nil — skipping state reset (mid-account-change?)")
            return
        }
        clearCanceledShareSentinel()
        let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
        logger.info("checkSharingStatus: no shares found — solo mode — \(elapsed, format: .fixed(precision: 1))ms")
        isShared = false
        isShareOwner = false
        partnerName = nil
        currentShare = nil
    }

    func persistUpdatedShare(_ share: CKShare) {
        logger.debug("persistUpdatedShare: routing to \(self.isShareOwner ? "private" : "shared") store")
        // Route to the correct store based on role
        let targetStore: NSPersistentStore?
        if isShareOwner {
            targetStore = persistenceController.privatePersistentStore
        } else {
            targetStore = persistenceController.sharedPersistentStore
        }
        guard let store = targetStore else {
            logger.warning("persistUpdatedShare: target store is nil")
            return
        }
        persistenceController.container.persistUpdatedShare(share, in: store) { _, error in
            if let error {
                logger.fault("persistUpdatedShare: FAILED — \(error.localizedDescription)")
            } else {
                logger.debug("persistUpdatedShare: success")
            }
        }
    }

    func prepareObjectForSharedSave(_ object: NSManagedObject) {
        guard isShared, !isShareOwner else { return }
        guard object.managedObjectContext != nil else {
            logger.error("prepareObjectForSharedSave: nil managedObjectContext")
            return
        }
        // Participant: assign to shared store so save goes to shared zone
        guard let sharedStore = persistenceController.sharedPersistentStore else {
            logger.warning("prepareObjectForSharedSave: shared store is nil")
            return
        }
        logger.debug("prepareObjectForSharedSave: assigning object to shared store")
        object.managedObjectContext?.assign(object, to: sharedStore)
    }

    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
        guard isShared, isShareOwner, let share = currentShare else { return }
        guard !objects.isEmpty else { return }
        // Guard: iCloud must be available
        guard FileManager.default.ubiquityIdentityToken != nil else {
            logger.error("shareObjectsToHouseholdIfNeeded: iCloud unavailable — saved locally only")
            return
        }
        logger.info("shareObjectsToHouseholdIfNeeded: sharing \(objects.count) objects to household")
        let shareOpStart = CFAbsoluteTimeGetCurrent()
        _ = try await persistenceController.container.share(objects, to: share)
        let shareOpElapsed = (CFAbsoluteTimeGetCurrent() - shareOpStart) * 1000
        logger.info("shareObjectsToHouseholdIfNeeded: success — \(shareOpElapsed, format: .fixed(precision: 1))ms")
    }

    func resetState() {
        logger.info("resetState: clearing cached sharing state")
        isShared = false
        isShareOwner = false
        partnerName = nil
        currentShare = nil
        backfillTask?.cancel()
        backfillTask = nil
        clearCanceledShareSentinel()
        clearBackfillMarker()
    }

    func cancelShare() async throws {
        logger.info("cancelShare: deleting current share")
        guard let share = currentShare else {
            logger.warning("cancelShare: no current share to cancel")
            return
        }

        guard FileManager.default.ubiquityIdentityToken != nil else {
            logger.error("cancelShare: no iCloud account")
            throw NSError(
                domain: "CloudSharingService",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to iCloud in Settings to manage sharing."]
            )
        }

        let container = CKContainer(identifier: Self.containerIdentifier)
        let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [share.recordID])
        operation.qualityOfService = .userInitiated

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    // Treat .unknownItem as success — share already deleted server-side
                    if let ckError = error as? CKError,
                       ckError.code == .partialFailure,
                       let partialErrors = ckError.partialErrorsByItemID,
                       partialErrors.values.allSatisfy({ ($0 as? CKError)?.code == .unknownItem }) {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            container.privateCloudDatabase.add(operation)
        }

        logger.info("cancelShare: share deleted from CloudKit")
        setCanceledShareSentinel(recordName: share.recordID.recordName)
        logger.debug("cancelShare: set sentinel for recordName=\(share.recordID.recordName)")
        isShared = false
        isShareOwner = false
        partnerName = nil
        currentShare = nil
    }

    // MARK: - Private

    /// Returns true if `recordName` matches a recently-canceled share within the TTL window.
    /// Pure query — does not mutate state. Callers clear the sentinel explicitly.
    private func isRecentlyCanceled(recordName: String) -> Bool {
        guard let canceled = canceledShareRecordName, canceled == recordName,
              let ts = canceledShareTimestamp else { return false }
        return Date().timeIntervalSince(ts) < Self.canceledShareTTL
    }

    private func setCanceledShareSentinel(recordName: String) {
        let now = Date()
        canceledShareRecordName = recordName
        canceledShareTimestamp = now
        UserDefaults.standard.set(recordName, forKey: Self.canceledShareKey)
        UserDefaults.standard.set(now, forKey: Self.canceledShareTimestampKey)
    }

    private func clearCanceledShareSentinel() {
        canceledShareRecordName = nil
        canceledShareTimestamp = nil
        UserDefaults.standard.removeObject(forKey: Self.canceledShareKey)
        UserDefaults.standard.removeObject(forKey: Self.canceledShareTimestampKey)
    }

    private func clearBackfillMarker() {
        backfilledShareRecordName = nil
        UserDefaults.standard.removeObject(forKey: Self.backfilledShareKey)
    }

    private func markBackfillComplete(for recordName: String) {
        backfilledShareRecordName = recordName
        UserDefaults.standard.set(recordName, forKey: Self.backfilledShareKey)
    }

    /// Schedules a background task to back-fill pre-invite expenses from the private
    /// default zone into the shared zone. Runs at most once per *successful*
    /// completion — failures leave both the in-memory and UserDefaults markers
    /// unset so the next `checkSharingStatus` call retries. A fresh share (different
    /// `recordName`) clears the marker via `clearBackfillMarker` in `createShare`.
    ///
    /// Runs at `.utility` priority because `container.share(_:to:)` holds the calling
    /// actor during a network round-trip — running it at the inherited `.userInteractive`
    /// priority would contend with UI rendering on large histories.
    private func scheduleBackfillIfNeeded(for share: CKShare) {
        let recordName = share.recordID.recordName
        guard backfilledShareRecordName != recordName else { return }
        guard backfillTask == nil else { return }
        logger.info("backfill: scheduling pre-invite expense back-fill for share=\(recordName)")
        backfillTask = Task(priority: .utility) { [weak self] in
            await self?.runBackfill(for: recordName)
        }
    }

    private func runBackfill(for recordName: String) async {
        defer { backfillTask = nil }
        guard let privateStore = persistenceController.privatePersistentStore else {
            logger.warning("backfill: private store unavailable — aborting")
            return
        }
        guard let share = currentShare, share.recordID.recordName == recordName else {
            logger.debug("backfill: share changed before run — aborting")
            return
        }

        let objectIDs: [NSManagedObjectID]
        do {
            objectIDs = try await fetchPrivateExpenseIDs(in: privateStore)
        } catch {
            // Core Data fetch errors surface as generic NSError with no retryability
            // signal — treat as permanent so checkSharingStatus doesn't spam retries.
            logger.error("backfill: fetch FAILED — marking complete to prevent retry storm — \(error.localizedDescription)")
            markBackfillComplete(for: recordName)
            return
        }

        guard !Task.isCancelled else {
            logger.debug("backfill: cancelled after fetch — aborting")
            return
        }

        let expensesToShare = hydrateDefaultZoneExpenses(ids: objectIDs, privateStore: privateStore)
        guard !expensesToShare.isEmpty else {
            logger.info("backfill: no default-zone expenses to share — marking complete")
            markBackfillComplete(for: recordName)
            return
        }

        logger.info("backfill: sharing \(expensesToShare.count) pre-invite expenses to household")
        let opStart = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await persistenceController.container.share(expensesToShare, to: share)
            let elapsed = (CFAbsoluteTimeGetCurrent() - opStart) * 1000
            logger.info("backfill: success — \(elapsed, format: .fixed(precision: 1))ms")
            markBackfillComplete(for: recordName)
        } catch {
            handleBackfillShareError(error, recordName: recordName)
        }
    }

    /// Fetches Expense ObjectIDs on a background context so a large history doesn't
    /// block the main actor. ObjectIDs are `Sendable` and can safely cross the
    /// background → main boundary for re-hydration in `hydrateDefaultZoneExpenses`.
    private func fetchPrivateExpenseIDs(
        in privateStore: NSPersistentStore
    ) async throws -> [NSManagedObjectID] {
        let bgContext = persistenceController.container.newBackgroundContext()
        return try await bgContext.perform {
            let request = NSFetchRequest<NSManagedObjectID>(entityName: "Expense")
            request.resultType = .managedObjectIDResultType
            request.affectedStores = [privateStore]
            return try bgContext.fetch(request)
        }
    }

    /// Re-hydrates ObjectIDs on the main viewContext and filters to objects still in
    /// the private default zone. Objects already migrated to the shared zone are
    /// skipped — re-sharing races the CloudKit export cycle and produces
    /// "Missing metadata for recordID" warnings per cloudkit-sync.md:94.
    private func hydrateDefaultZoneExpenses(
        ids: [NSManagedObjectID],
        privateStore: NSPersistentStore
    ) -> [NSManagedObject] {
        let viewContext = persistenceController.container.viewContext
        return ids.compactMap { id in
            guard let object = try? viewContext.existingObject(with: id) else { return nil }
            return object.objectID.persistentStore == privateStore ? object : nil
        }
    }

    /// Classifies a back-fill share error and decides whether to retry or give up.
    /// Transient CKErrors (network/throttling) leave the marker unset so the next
    /// `checkSharingStatus` retries. Permanent CKErrors (quota, permissions, schema)
    /// mark complete to stop the retry storm — the underlying issue must be resolved
    /// by the user. Non-CKError exceptions also mark complete: infinite retries on
    /// an unidentified error are worse than silent failure, and the log gives the
    /// user visibility via Console.app.
    private func handleBackfillShareError(_ error: Error, recordName: String) {
        if let ckError = error as? CKError, Self.isTransientBackfillError(ckError) {
            logger.error("backfill: share FAILED (transient, will retry) — code=\(ckError.code.rawValue) — \(error.localizedDescription)")
            return
        }
        logger.error("backfill: share FAILED (permanent, marking complete to prevent retry storm) — \(error.localizedDescription)")
        markBackfillComplete(for: recordName)
    }

    /// CKError codes that justify a retry on the next `checkSharingStatus` call.
    /// Everything else — `.quotaExceeded`, `.permissionFailure`, `.serverRejectedRequest`,
    /// `.badContainer`, `.notAuthenticated`, etc. — is treated as permanent so the
    /// retry loop terminates instead of spamming CloudKit on every sync notification.
    private static func isTransientBackfillError(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    /// Fetches the first non-canceled CKShare from a persistent store, or nil.
    /// Iterates past sentinel-suppressed entries so a stale canceled share at index 0
    /// cannot mask a valid new share at index 1 during the mirror catch-up window.
    private func fetchActiveShare(from store: NSPersistentStore?, label: String) -> CKShare? {
        guard let store else {
            logger.debug("checkSharingStatus: \(label) store is nil")
            return nil
        }
        do {
            let shares = try persistenceController.container.fetchShares(in: store)
            logger.debug("checkSharingStatus: \(shares.count) shares in \(label) store")
            for share in shares {
                if isRecentlyCanceled(recordName: share.recordID.recordName) {
                    logger.info("checkSharingStatus: ignoring stale canceled share in \(label) store")
                    continue
                }
                return share
            }
            return nil
        } catch {
            logger.error("checkSharingStatus: failed to fetch from \(label) store — \(error.localizedDescription)")
            return nil
        }
    }

    private func extractPartnerInfo(from share: CKShare) {
        if !isShareOwner {
            // Participant path: we accepted the owner's share — the owner IS our partner.
            // share.owner is populated from the accepted share metadata and is more reliable
            // than iterating share.participants, which may be incomplete in cached CKShares.
            if let nameComponents = share.owner.userIdentity.nameComponents {
                partnerName = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                partnerName = "Partner"
            }
            logger.info("extractPartnerInfo: participant mode — partner resolved=\(self.partnerName != nil)")
            return
        }

        // Owner path: look for accepted participants (excluding ourselves).
        // Guard against nil ownerRecordID — identity may not be resolved yet in cached CKShares.
        // Without this guard, nil == nil passes all participants through the filter,
        // potentially returning the owner as their own partner.
        guard let ownerRecordID = share.owner.userIdentity.userRecordID else {
            logger.warning("extractPartnerInfo: owner userRecordID not yet resolved — deferring")
            partnerName = nil
            return
        }
        let otherParticipants = share.participants.filter { participant in
            participant.userIdentity.userRecordID != ownerRecordID
        }

        if let partner = otherParticipants.first(where: { $0.acceptanceStatus == .accepted }) {
            if let nameComponents = partner.userIdentity.nameComponents {
                partnerName = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                partnerName = "Partner"
            }
            logger.info("extractPartnerInfo: owner mode — partner resolved=\(self.partnerName != nil)")
        } else {
            logger.debug("extractPartnerInfo: owner mode — no accepted partner yet (\(otherParticipants.count) other participants)")
            partnerName = nil
        }
    }
}

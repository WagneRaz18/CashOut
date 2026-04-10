import Foundation
import CloudKit
@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CloudSharingService")

/// Canonical state of the household sharing relationship.
///
/// The four cases map to the four user-perceivable phases of CloudKit sharing:
/// - `.solo`: no CKShare exists in either store.
/// - `.draft`: a CKShare exists locally (created by `container.share(objects, to: nil)`),
///   but no invitation has been dispatched yet. This is the window between `createShare()`
///   success and either invite dispatch (→ `.pending`) or sheet cancellation (→ `.solo`).
/// - `.pending`: the owner sent an invitation (`participants.count > 1`) but no partner
///   has accepted yet.
/// - `.connected`: at least one partner has accepted the invitation.
///
/// The associated value on `.connected` makes `partnerName` type-safely inaccessible
/// in any other state, eliminating the class of bugs where a draft or pending share
/// could be mistaken for a connected one.
enum SharingState: Equatable {
    case solo
    case draft
    case pending
    case connected(partnerName: String?)
}

@MainActor
protocol CloudSharingServiceProtocol {
    var state: SharingState { get }
    var isShareOwner: Bool { get }
    func createShare(for objects: [NSManagedObject]) async throws -> (CKShare, CKContainer)
    func checkSharingStatus() async
    func persistUpdatedShare(_ share: CKShare)
    func prepareObjectForSharedSave(_ object: NSManagedObject)
    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws
    func resetState()
    func cancelShare() async throws
    func finalizeShareOutcome(_ updatedShare: CKShare?) async
}

@MainActor
@Observable
final class CloudSharingService: CloudSharingServiceProtocol {
    static let shared = CloudSharingService()

    var state: SharingState = .solo

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
        isShareOwner = true
        share[CKShare.SystemFieldKey.title] = "CashOut Household"
        // Transition to .draft. The share exists in CloudKit but no invite has been
        // dispatched yet. `finalizeShareOutcome` will transition to `.pending` on
        // successful invite, or back to `.solo` with orphan cleanup on cancel.
        state = .draft
        logger.info("createShare: new share created successfully (state=.draft)")
        return (share, CKContainer(identifier: Self.containerIdentifier))
    }

    func checkSharingStatus() async {
        logger.info("checkSharingStatus: checking stores for shares")
        let checkStart = CFAbsoluteTimeGetCurrent()

        if let share = fetchActiveShare(from: persistenceController.privatePersistentStore, label: "private") {
            // Capture the session-boundary signal BEFORE any state mutation.
            // `currentShare` is only ever set by in-session code paths (`createShare`,
            // this method, `apply`, `finalizeShareOutcome`) and reset by
            // `transitionToSolo`/`cancelShare`/`resetState`. At service init it is nil.
            // If we find a share that classifies as `.draft` and `currentShare` was nil
            // on entry, no in-session code created it — it's an orphan from a previous
            // session (crash, force-quit, or pre-fix buggy code). Clean it up rather
            // than preserving stale `.draft` state across session boundaries.
            let wasCurrentShareNil = (currentShare == nil)
            let classified = classify(share: share, isOwner: true)

            if classified == .draft && wasCurrentShareNil {
                logger.warning("checkSharingStatus: startup orphan .draft detected — cleaning up server-side")
                // Point `cancelShare` at the orphan: it reads `currentShare` as its target.
                // On success, cancelShare sets the sentinel and routes through
                // `transitionToSolo(clearSentinel: false)` to reset state atomically.
                isShareOwner = true
                currentShare = share
                do {
                    try await cancelShare()
                } catch {
                    logger.fault("checkSharingStatus: startup orphan cleanup FAILED — \(error.localizedDescription)")
                    // cancelShare threw before reaching its state reset, so we're now
                    // holding stale `currentShare`/`isShareOwner` values pointing at the
                    // orphan. Restore the session invariant — `state == .solo` implies
                    // `currentShare == nil` and `isShareOwner == false` — so a subsequent
                    // checkSharingStatus in the same session (e.g., triggered by a remote
                    // change notification) can re-attempt the orphan cleanup via the
                    // `wasCurrentShareNil` path. `clearSentinel: false` because the
                    // sentinel state is whatever cancelShare left it — don't touch it.
                    transitionToSolo(clearSentinel: false)
                }
                return
            }

            isShareOwner = true
            currentShare = share
            state = classified
            // Back-fill pre-invite expenses into the shared zone exactly once per
            // unique share. Gate on `hasCommittedShare` (.pending or .connected) —
            // running backfill for a `.draft` would move expenses into a zone attached
            // to an uncommitted share, orphaning them if the user cancels.
            if hasCommittedShare {
                scheduleBackfillIfNeeded(for: share)
            } else {
                logger.debug("checkSharingStatus: draft share — skipping backfill until committed")
            }
            let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
            logger.info("checkSharingStatus: found share in private store (owner, state=\(String(describing: self.state))) — \(elapsed, format: .fixed(precision: 1))ms")
            return
        }

        if let share = fetchActiveShare(from: persistenceController.sharedPersistentStore, label: "shared") {
            isShareOwner = false
            currentShare = share
            state = classify(share: share, isOwner: false)
            let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
            logger.info("checkSharingStatus: found share in shared store (participant, state=\(String(describing: self.state))) — \(elapsed, format: .fixed(precision: 1))ms")
            return
        }

        // No shares found (or only stale canceled shares).
        guard persistenceController.privatePersistentStore != nil ||
              persistenceController.sharedPersistentStore != nil else {
            logger.warning("checkSharingStatus: both stores nil — skipping state reset (mid-account-change?)")
            return
        }

        // Mid-sheet guard: if the user is currently composing an invite (state == .draft)
        // and a remote change notification triggered this refresh before the fresh share
        // replicated back from CloudKit, preserve .draft so we don't nuke the in-progress
        // draft and force a duplicate share on re-present. The draft is protected by
        // explicit transitions in createShare / finalizeShareOutcome only.
        if state == .draft {
            logger.debug("checkSharingStatus: preserving .draft during mid-sheet refresh")
            return
        }

        clearCanceledShareSentinel()
        let elapsed = (CFAbsoluteTimeGetCurrent() - checkStart) * 1000
        logger.info("checkSharingStatus: no shares found — solo mode — \(elapsed, format: .fixed(precision: 1))ms")
        state = .solo
        isShareOwner = false
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
        // Participant path only: the participant accepted the owner's share and
        // is in `.connected`. Route new objects through the shared store so they
        // land in the shared zone. Owner-side state does not affect this guard.
        guard !isShareOwner, case .connected = state else { return }
        guard object.managedObjectContext != nil else {
            logger.error("prepareObjectForSharedSave: nil managedObjectContext")
            return
        }
        guard let sharedStore = persistenceController.sharedPersistentStore else {
            logger.warning("prepareObjectForSharedSave: shared store is nil")
            return
        }
        logger.debug("prepareObjectForSharedSave: assigning object to shared store")
        object.managedObjectContext?.assign(object, to: sharedStore)
    }

    func shareObjectsToHouseholdIfNeeded(_ objects: [NSManagedObject]) async throws {
        // Owner path only, and only after the invitation is committed (pending or
        // connected). While in `.draft` we deliberately do NOT route new expenses
        // into the shared zone — a user cancelling the invite would otherwise leak
        // expenses into a zone that is about to be deleted.
        guard isShareOwner, hasCommittedShare, let share = currentShare else { return }
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
        state = .solo
        isShareOwner = false
        currentShare = nil
        backfillTask?.cancel()
        backfillTask = nil
        clearCanceledShareSentinel()
        clearBackfillMarker()
    }

    /// True when there is a committed, sent invitation: the owner has dispatched an
    /// invite (`.pending`) or a partner has accepted (`.connected`). Explicitly false
    /// for `.draft` — expenses must not be routed into the shared zone while the user
    /// is still composing an invitation that may yet be cancelled.
    var hasCommittedShare: Bool {
        switch state {
        case .pending, .connected: return true
        case .solo, .draft: return false
        }
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
        // Route through the centralized helper so every `.solo` transition resets
        // state/isShareOwner/currentShare in lockstep. `clearSentinel: false` because
        // we just set it above — clearing it would defeat the purpose of the TTL guard.
        transitionToSolo(clearSentinel: false)
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

    /// Pure classification of a CKShare into a `SharingState`. No side effects — the
    /// caller is responsible for assigning the result to `self.state`.
    ///
    /// - Participant side: the presence of the share in the shared store implies we
    ///   accepted it, so we are always in `.connected` with the owner as the partner.
    /// - Owner side: `.draft` if there are no invited participants, `.connected` if at
    ///   least one has `.accepted`, `.pending` otherwise.
    ///
    /// The owner-side nil guard on `share.owner.userIdentity.userRecordID` is
    /// critical: if the identity is unresolved, `nil != nil` would pass the owner
    /// through the filter and the owner could end up as its own partner. In that
    /// defensive case we return `.draft` rather than committing to a `.pending` or
    /// `.connected` state we can't verify.
    private func classify(share: CKShare, isOwner: Bool) -> SharingState {
        if !isOwner {
            // Participant path: we accepted the owner's share. The partner IS the owner.
            let name: String?
            if let nameComponents = share.owner.userIdentity.nameComponents {
                name = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                name = nil
            }
            return .connected(partnerName: name)
        }

        // Owner path — nil-guard the identity resolution
        guard let ownerRecordID = share.owner.userIdentity.userRecordID else {
            logger.warning("classify: owner userRecordID unresolved — returning .draft")
            return .draft
        }

        let others = share.participants.filter { participant in
            participant.userIdentity.userRecordID != ownerRecordID
        }

        guard !others.isEmpty else {
            // Only owner — no invites dispatched.
            return .draft
        }

        if let accepted = others.first(where: { $0.acceptanceStatus == .accepted }) {
            let name: String?
            if let nameComponents = accepted.userIdentity.nameComponents {
                name = PersonNameComponentsFormatter.localizedString(
                    from: nameComponents, style: .short, options: []
                )
            } else {
                name = nil
            }
            return .connected(partnerName: name)
        }

        return .pending
    }

    // MARK: - Share Outcome Finalization

    /// Called from the ViewModel whenever the share sheet is dismissed, regardless of
    /// which path (delegate callback or interactive dismiss). Owns all classification
    /// and cleanup logic so the ViewModel stays agnostic of CloudKit details.
    ///
    /// **Path A — delegate handed us a share.** This fires on
    /// `cloudSharingControllerDidSaveShare`, which per UIKit docs can trigger on
    /// invitation dispatch AND on permission changes inside the sheet. We cannot
    /// distinguish these from the callback alone, so we fetch the authoritative state
    /// from CloudKit via `fetchFreshShare` and classify from that.
    ///
    /// If the fresh fetch fails with `CKError.unknownItem` the server is telling us
    /// the share is gone — transition to `.solo`. For any other error (network,
    /// throttling, freshly-created share that hasn't propagated yet) fall back to
    /// classifying the delegate-provided share and do NOT trigger orphan cleanup.
    /// Cancelling on a transient failure would delete a legitimately-created share
    /// during the CloudKit propagation window.
    ///
    /// **Path B — nil share.** Either the user swipe-dismissed without taking any
    /// action, or `didStopSharing`/`failedToSaveShareWithError` fired. We use the
    /// current state to disambiguate: `.draft` means orphan cleanup, `.pending` or
    /// `.connected` means UIKit already deleted the share remotely (Stop Sharing) so
    /// we just refresh from stores.
    func finalizeShareOutcome(_ updatedShare: CKShare?) async {
        if let updatedShare {
            do {
                let fresh = try await fetchFreshShare(recordID: updatedShare.recordID)
                let classified = classify(share: fresh, isOwner: isShareOwner)
                logger.info("finalizeShareOutcome: fresh classification=\(String(describing: classified))")
                await apply(classification: classified, authoritativeShare: fresh, delegateShare: updatedShare)
            } catch let error where Self.isUnknownItemError(error) {
                // Server confirms the share does not exist. Safe to transition to solo.
                // Handles both the direct `.unknownItem` form and the `.partialFailure`
                // envelope that some CKFetchRecordsOperation failure paths wrap it in.
                logger.info("finalizeShareOutcome: server confirmed share absent (.unknownItem)")
                transitionToSolo(clearSentinel: true)
            } catch {
                // Transient failure (network, propagation lag). Fall back to the delegate
                // share — do NOT call cancelShare on transient errors.
                logger.warning("finalizeShareOutcome: fresh fetch failed (\(error.localizedDescription)) — falling back to delegate share")
                let classified = classify(share: updatedShare, isOwner: isShareOwner)
                await apply(classification: classified, authoritativeShare: updatedShare, delegateShare: updatedShare)
            }
            return
        }

        // Path B: nil share
        switch state {
        case .draft:
            logger.info("finalizeShareOutcome: draft state + nil share — cleaning up orphan")
            do {
                try await cancelShare()
            } catch {
                logger.fault("finalizeShareOutcome: draft cleanup FAILED — \(error.localizedDescription)")
                // cancelShare didn't complete. Let checkSharingStatus re-derive on next refresh
                // rather than forcing .solo and leaving a real orphan server-side.
                await checkSharingStatus()
            }
        case .pending, .connected:
            // Stop Sharing path — UIKit already deleted server-side. Refresh to derive solo.
            logger.info("finalizeShareOutcome: stop-sharing path — refreshing state from stores")
            await checkSharingStatus()
        case .solo:
            logger.debug("finalizeShareOutcome: already solo — no-op")
        }
    }

    private func apply(
        classification: SharingState,
        authoritativeShare: CKShare,
        delegateShare: CKShare
    ) async {
        switch classification {
        case .draft:
            // The delegate handed us a share but it has zero invited participants.
            // This is an orphan — clean up.
            logger.info("finalizeShareOutcome: classified .draft after delegate — cleaning up orphan")
            do {
                try await cancelShare()
            } catch {
                logger.fault("finalizeShareOutcome: orphan cleanup FAILED — \(error.localizedDescription)")
                await checkSharingStatus()
            }
        case .pending, .connected:
            // Persist whatever the delegate handed us (that's what UIKit last touched)
            // and update cached state from the fresh authoritative share.
            persistUpdatedShare(delegateShare)
            currentShare = authoritativeShare
            state = classification
        case .solo:
            // `classify` never returns `.solo` directly, but the enum switch must be
            // exhaustive. If we do reach here, mirror the full solo-transition contract.
            transitionToSolo(clearSentinel: true)
        }
    }

    /// Full solo-state transition: clears `state`, `isShareOwner`, `currentShare`, and
    /// (optionally) the canceled-share sentinel. Every `.solo` transition must go
    /// through this helper to prevent stale `isShareOwner` or sentinel leakage across
    /// paths — both were bugs caught in code review.
    private func transitionToSolo(clearSentinel: Bool) {
        state = .solo
        isShareOwner = false
        currentShare = nil
        if clearSentinel {
            clearCanceledShareSentinel()
        }
    }

    /// Returns true if the error represents a server-confirmed "record does not exist"
    /// condition — either a direct `CKError.unknownItem` or a `CKError.partialFailure`
    /// envelope whose per-item errors are all `.unknownItem`. All other CKErrors
    /// (network, throttling, propagation lag) must be treated as transient and must NOT
    /// trigger a `.solo` transition, or we'll delete legitimately-created shares during
    /// CloudKit's cache propagation window.
    private static func isUnknownItemError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        if ckError.code == .unknownItem { return true }
        if ckError.code == .partialFailure,
           let partials = ckError.partialErrorsByItemID,
           !partials.isEmpty,
           partials.values.allSatisfy({ ($0 as? CKError)?.code == .unknownItem }) {
            return true
        }
        return false
    }

    /// Fetches the authoritative CKShare from CloudKit (not the local Core Data mirror).
    /// Routes to the correct database based on role.
    ///
    /// Continuation safety: the completion-block API for `CKFetchRecordsOperation` has
    /// two result callbacks (`perRecordResultBlock` and `fetchRecordsResultBlock`).
    /// This wrapper captures per-record results into locals and resumes the continuation
    /// exactly once from `fetchRecordsResultBlock`. Double-resume or resume-never both
    /// cause undefined behavior / hangs in Swift structured concurrency.
    private func fetchFreshShare(recordID: CKRecord.ID) async throws -> CKShare {
        let container = CKContainer(identifier: Self.containerIdentifier)
        let database = isShareOwner ? container.privateCloudDatabase : container.sharedCloudDatabase

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CKShare, Error>) in
            let op = CKFetchRecordsOperation(recordIDs: [recordID])
            op.qualityOfService = .userInitiated

            var fetchedShare: CKShare?
            var perRecordError: Error?

            op.perRecordResultBlock = { _, result in
                switch result {
                case .success(let record):
                    if let share = record as? CKShare {
                        fetchedShare = share
                    } else {
                        perRecordError = CKError(.internalError)
                    }
                case .failure(let error):
                    perRecordError = error
                }
            }

            op.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    if let share = fetchedShare {
                        continuation.resume(returning: share)
                    } else if let perRecordError {
                        continuation.resume(throwing: perRecordError)
                    } else {
                        continuation.resume(throwing: CKError(.unknownItem))
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(op)
        }
    }
}

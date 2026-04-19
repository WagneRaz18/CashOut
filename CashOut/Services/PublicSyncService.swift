import Foundation
import CloudKit
@preconcurrency import CoreData
import Network
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "PublicSyncService")

/// Syncs CashOut's `Expense` and `Category` records between two paired devices via the
/// CloudKit public database, filtered by a shared `householdCode`.
///
/// **Why the public database and not `.shared` via CKShare?** The CKShare invitation flow
/// proved irreducibly fragile — URL routing depends on iMessage/Apple Mail (WhatsApp breaks
/// it), scene-delegate class lookup silently failed on some builds. The public database
/// has no invitation step: both devices store the same 8-char household code and write/read
/// records tagged with it. Privacy is preserved because the container is scoped to this
/// app and the code space (~1.1T combinations) makes enumeration infeasible.
///
/// **Why not `NSPersistentCloudKitContainer` with `.public` scope?** Per WWDC20 session
/// 10650, the framework's public-scope implementation polls every 30 minutes and does not
/// receive silent pushes — unacceptable for a real-time expense tracker. Raw
/// `CKQuerySubscription` on `CKContainer.publicCloudDatabase` DOES receive silent pushes
/// (`shouldSendContentAvailable = true`), which is why this service uses raw CKDatabase
/// rather than routing through the persistent container.
///
/// **Data flow:**
/// - Write: repository saves to Core Data (private store) → calls `upsert(record:)` →
///   this service writes to public DB via `CKModifyRecordsOperation(savePolicy: .allKeys)`.
/// - Read: CKQuerySubscription fires silent push → `AppDelegate.didReceiveRemoteNotification`
///   calls `handleRemoteNotification(userInfo:)` → this service fetches changed records
///   since `lastFetchDate` and upserts them into the Core Data private store on a
///   background context. FRC observers then update the UI automatically.
@MainActor
@Observable
final class PublicSyncService: PublicSyncServiceProtocol {
    static let shared = PublicSyncService()

    @ObservationIgnored private let container: CKContainer
    @ObservationIgnored private let publicDB: CKDatabase
    @ObservationIgnored private let persistence: PersistenceController
    @ObservationIgnored private let householdService: HouseholdService
    @ObservationIgnored private let pathMonitor: NWPathMonitor
    @ObservationIgnored private let monitorQueue = DispatchQueue(label: "com.wagneraz.CashOut.PublicSyncService.pathMonitor")

    /// In-memory retry queue. Records that failed with a transient error are held here
    /// until `NWPathMonitor` reports reachability, then resubmitted. Record IDs are also
    /// persisted to `UserDefaults` so a mid-outbox app kill doesn't lose pending writes —
    /// on launch, `restoreOutboxFromPersistence()` rebuilds the `CKRecord` from Core Data.
    @ObservationIgnored private var outbox: [CKRecord.ID: CKRecord] = [:]

    /// Debounce handle for fetchChanges — silent pushes can arrive rapidly.
    @ObservationIgnored private var fetchDebounceTask: Task<Void, Never>?

    /// Debounce/guard for drainOutbox — NWPathMonitor can fire multiple times per WiFi join.
    @ObservationIgnored private var drainOutboxTask: Task<Void, Never>?
    @ObservationIgnored private var isDrainingOutbox = false

    private static let containerIdentifier = "iCloud.com.wagneraz.CashOut"
    private static let expenseRecordType = "Expense"
    private static let categoryRecordType = "Category"
    private static let lastFetchDateKey = "CashOut.publicSyncLastFetchDate"
    private static let outboxRecordIDsKey = "CashOut.publicSyncOutboxRecordIDs"

    /// Field name shared across both record types. Must be QUERYABLE in CloudKit Dashboard.
    /// `nonisolated` so the background-context merge helpers can read them without hopping.
    nonisolated(unsafe) static let householdCodeField = "householdCode"
    nonisolated(unsafe) static let modifiedAtField = "modifiedAt"
    nonisolated(unsafe) static let isSoftDeletedField = "isSoftDeleted"

    init(
        persistence: PersistenceController = .shared,
        householdService: HouseholdService = .shared
    ) {
        self.persistence = persistence
        self.householdService = householdService
        self.container = CKContainer(identifier: Self.containerIdentifier)
        self.publicDB = container.publicCloudDatabase
        self.pathMonitor = NWPathMonitor()
        logger.debug("PublicSyncService.init")
        startPathMonitor()
        restoreOutboxFromPersistence()
    }

    // MARK: - Subscription Registration

    /// Registers silent-push subscriptions for Expense and Category record types matching
    /// the current household code. Safe to call on every launch — CloudKit replaces
    /// subscriptions on duplicate IDs, and any per-item errors are inspected explicitly
    /// so a schema-missing failure in Production is surfaced instead of being swallowed
    /// as "already exists."
    ///
    /// **Prerequisite:** `householdCode` field must be marked QUERYABLE in the CloudKit
    /// Dashboard schema for both record types, or save will fail in production.
    func registerSubscriptions() async {
        guard let code = householdService.householdCode else {
            logger.info("registerSubscriptions: no household code — skipping")
            return
        }

        let expenseSubID = "cashout-expense-v1-\(code)"
        let categorySubID = "cashout-category-v1-\(code)"
        let predicate = NSPredicate(format: "%K == %@", Self.householdCodeField, code)

        let expenseSub = CKQuerySubscription(
            recordType: Self.expenseRecordType,
            predicate: predicate,
            subscriptionID: expenseSubID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let expenseInfo = CKQuerySubscription.NotificationInfo()
        expenseInfo.shouldSendContentAvailable = true
        expenseSub.notificationInfo = expenseInfo

        let categorySub = CKQuerySubscription(
            recordType: Self.categoryRecordType,
            predicate: predicate,
            subscriptionID: categorySubID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let categoryInfo = CKQuerySubscription.NotificationInfo()
        categoryInfo.shouldSendContentAvailable = true
        categorySub.notificationInfo = categoryInfo

        do {
            _ = try await publicDB.modifySubscriptions(
                saving: [expenseSub, categorySub],
                deleting: []
            )
            logger.info("registerSubscriptions: saved Expense + Category subscriptions")
        } catch let ckError as CKError where Self.isBenignSubscriptionError(ckError) {
            logger.info("registerSubscriptions: subscriptions already present — OK (\(ckError.code.rawValue))")
        } catch {
            // Crucially, we do NOT silently swallow — this is the hook that tells us
            // the CloudKit Dashboard schema is out of date in Production.
            logger.error("registerSubscriptions: FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Inspects a CKError from `modifySubscriptions` and returns true ONLY when every
    /// per-item error indicates "already exists on server" (`.serverRecordChanged` on a
    /// subscription save = duplicate). Top-level `.serverRejectedRequest` without a
    /// partial-errors dict is treated as a real failure so production schema issues
    /// surface in logs instead of being silently cached as "registered."
    private static func isBenignSubscriptionError(_ error: CKError) -> Bool {
        guard let perItem = error.partialErrorsByItemID,
              !perItem.isEmpty else { return false }
        for (_, itemError) in perItem {
            guard let ckItem = itemError as? CKError else { return false }
            switch ckItem.code {
            case .serverRecordChanged, .unknownItem:
                continue
            default:
                return false
            }
        }
        return true
    }

    /// Removes subscriptions on unpair. Best-effort; errors are logged but don't block.
    func removeSubscriptions() async {
        guard let code = householdService.householdCode else { return }
        let expenseSubID = "cashout-expense-v1-\(code)"
        let categorySubID = "cashout-category-v1-\(code)"
        do {
            _ = try await publicDB.modifySubscriptions(
                saving: [],
                deleting: [expenseSubID, categorySubID]
            )
            logger.info("removeSubscriptions: subscriptions deleted")
        } catch {
            logger.warning("removeSubscriptions: FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Write Path (upsert / softDelete)

    /// Upserts an Expense record to the public database. No-op if no household code.
    func upsert(expense: Expense) {
        guard let code = householdService.householdCode else { return }
        guard let id = expense.id else { return }

        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.expenseRecordType, recordID: recordID)
        record[Self.householdCodeField] = code as CKRecordValue
        record["id"] = id.uuidString as CKRecordValue
        record["amount"] = expense.amount as CKRecordValue
        record["note"] = (expense.note ?? "") as CKRecordValue
        record["categoryID"] = (expense.categoryID?.uuidString ?? "") as CKRecordValue
        record["createdByDisplayName"] = (expense.createdByDisplayName ?? "") as CKRecordValue
        record["createdAt"] = (expense.createdAt ?? Date()) as CKRecordValue
        record[Self.modifiedAtField] = (expense.modifiedAt ?? Date()) as CKRecordValue
        record[Self.isSoftDeletedField] = (expense.isSoftDeleted ? 1 : 0) as CKRecordValue

        submit(record: record)
    }

    /// Upserts a Category record to the public database. No-op if no household code.
    func upsert(category: Category) {
        guard let code = householdService.householdCode else { return }
        guard let id = category.id else { return }

        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.categoryRecordType, recordID: recordID)
        record[Self.householdCodeField] = code as CKRecordValue
        record["id"] = id.uuidString as CKRecordValue
        record["name"] = (category.name ?? "") as CKRecordValue
        record["iconName"] = (category.iconName ?? "") as CKRecordValue
        record["colorName"] = (category.colorName ?? "") as CKRecordValue
        record["isDefault"] = (category.isDefault ? 1 : 0) as CKRecordValue
        record["sortOrder"] = Int64(category.sortOrder) as CKRecordValue
        record[Self.modifiedAtField] = (category.modifiedAt ?? Date()) as CKRecordValue
        record[Self.isSoftDeletedField] = (category.isSoftDeleted ? 1 : 0) as CKRecordValue

        submit(record: record)
    }

    /// Internal submit path — uses `.allKeys` save policy for true last-writer-wins.
    /// On transient errors, parks the record in `outbox` for retry on reachability.
    private func submit(record: CKRecord) {
        let operation = CKModifyRecordsOperation(
            recordsToSave: [record],
            recordIDsToDelete: nil
        )
        operation.savePolicy = .allKeys
        operation.qualityOfService = .userInitiated
        operation.isAtomic = false

        // Capture Sendable-safe values BEFORE the Task hop — CKRecord itself is not
        // Sendable and cannot cross actor boundaries safely.
        let capturedRecordID = record.recordID
        let capturedRecordType = record.recordType

        operation.modifyRecordsResultBlock = { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.outbox.removeValue(forKey: capturedRecordID)
                    self.persistOutboxKeys()
                    logger.debug("submit: upserted \(capturedRecordType) \(capturedRecordID.recordName)")
                case .failure(let error):
                    if Self.isTransient(error) {
                        self.outbox[capturedRecordID] = record
                        self.persistOutboxKeys()
                        logger.warning("submit: transient failure — parked in outbox — \(error.localizedDescription, privacy: .public)")
                    } else {
                        self.outbox.removeValue(forKey: capturedRecordID)
                        self.persistOutboxKeys()
                        logger.error("submit: permanent FAILURE — dropping — \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }

        publicDB.add(operation)
    }

    // MARK: - Read Path (fetchChanges)

    /// Debounced entry point for remote notifications. Coalesces rapid pushes. The
    /// AppDelegate's fetchCompletionHandler is expected to return eagerly; the actual
    /// fetch continues in this task independently.
    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        // Inspect CKNotification. If parsing succeeds AND the container identifier is
        // BOTH non-nil AND mismatched, bail out. If parsing fails or identifier is nil,
        // fall through and process — CloudKit does not populate the field on every
        // subscription-push shape, and we would rather over-fetch than drop a real push.
        if let notif = CKNotification(fromRemoteNotificationDictionary: userInfo),
           let notifContainer = notif.containerIdentifier,
           notifContainer != Self.containerIdentifier {
            logger.debug("handleRemoteNotification: different container (\(notifContainer, privacy: .public)) — ignoring")
            return
        }
        logger.info("handleRemoteNotification: scheduling debounced fetch")
        fetchDebounceTask?.cancel()
        fetchDebounceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 500_000_000)
            } catch is CancellationError { return } catch { return }
            guard !Task.isCancelled else { return }
            await self.fetchChanges()
        }
    }

    /// Queries the public database for records modified since `lastFetchDate` and upserts
    /// them into the local Core Data private store. Soft-deleted records tombstone the
    /// local copy.
    ///
    /// Uses `modifiedAt >= lastFetchDate` (inclusive) so a record whose `modifiedAt` ties
    /// the cursor is never skipped. After a successful merge, the cursor advances to the
    /// largest `modifiedAt` observed — stamping it AFTER the fetch avoids the race where
    /// a record arrives between `Date()` and query execution.
    func fetchChanges() async {
        guard let code = householdService.householdCode else {
            logger.debug("fetchChanges: no household code — skipping")
            return
        }
        let lastDate = UserDefaults.standard.object(forKey: Self.lastFetchDateKey) as? Date ?? .distantPast
        logger.info("fetchChanges: since \(lastDate)")

        do {
            let expenseRecords = try await fetchRecords(
                recordType: Self.expenseRecordType,
                householdCode: code,
                modifiedAtOrAfter: lastDate
            )
            let categoryRecords = try await fetchRecords(
                recordType: Self.categoryRecordType,
                householdCode: code,
                modifiedAtOrAfter: lastDate
            )
            logger.info("fetchChanges: \(expenseRecords.count) expenses + \(categoryRecords.count) categories to merge")

            if !expenseRecords.isEmpty || !categoryRecords.isEmpty {
                try await mergeIntoCoreData(expenses: expenseRecords, categories: categoryRecords)
            }

            // Advance cursor to the newest modifiedAt actually observed — never ahead
            // of the data itself. Fall back to the previous cursor if both lists empty.
            let observedMax = Self.maxModifiedAt(in: expenseRecords + categoryRecords) ?? lastDate
            UserDefaults.standard.set(observedMax, forKey: Self.lastFetchDateKey)
            logger.info("fetchChanges: completed — cursor advanced to \(observedMax)")
        } catch {
            logger.error("fetchChanges: FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func maxModifiedAt(in records: [CKRecord]) -> Date? {
        records.compactMap { $0[Self.modifiedAtField] as? Date }.max()
    }

    /// Runs a single `CKQueryOperation` for the given record type with `householdCode`
    /// and `modifiedAt >= lastDate` predicates. Returns all matching records.
    private func fetchRecords(
        recordType: String,
        householdCode: String,
        modifiedAtOrAfter: Date
    ) async throws -> [CKRecord] {
        let predicate = NSPredicate(
            format: "%K == %@ AND %K >= %@",
            Self.householdCodeField, householdCode,
            Self.modifiedAtField, modifiedAtOrAfter as NSDate
        )
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Self.modifiedAtField, ascending: true)]

        var accumulated: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor? = nil

        repeat {
            let (matchResults, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)
            if let cursor {
                (matchResults, nextCursor) = try await publicDB.records(continuingMatchFrom: cursor)
            } else {
                (matchResults, nextCursor) = try await publicDB.records(matching: query)
            }
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    accumulated.append(record)
                }
            }
            cursor = nextCursor
        } while cursor != nil

        return accumulated
    }

    /// Merges CKRecords into the local Core Data private store on a background context.
    /// Soft-deleted records set `isSoftDeleted = true` on the local copy (tombstone),
    /// which the FRC predicate filters out of the UI.
    private func mergeIntoCoreData(expenses: [CKRecord], categories: [CKRecord]) async throws {
        let context = persistence.container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyStoreTrump

        try await context.perform {
            for record in expenses {
                try Self.mergeExpense(record: record, context: context)
            }
            for record in categories {
                try Self.mergeCategory(record: record, context: context)
            }

            if context.hasChanges {
                try context.save()
                logger.info("mergeIntoCoreData: saved \(expenses.count + categories.count) records")
            }
        }
    }

    /// `nonisolated static` — must run on whatever thread `context.perform {}` provides,
    /// NOT the main actor. Taking no instance state and receiving the context + record
    /// as parameters lets us escape class-level `@MainActor` isolation safely.
    nonisolated private static func mergeExpense(record: CKRecord, context: NSManagedObjectContext) throws {
        guard let idString = record["id"] as? String, let id = UUID(uuidString: idString) else { return }

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        // `id as NSUUID` is the correct ObjC bridge for Core Data UUID predicates —
        // `as CVarArg` silently matches nothing (documented at cloudkit-sync.md:139).
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first
        let expense = existing ?? Expense(context: context)

        expense.id = id
        if let amt = record["amount"] as? Int64 { expense.amount = amt }
        expense.note = record["note"] as? String
        if let catIDString = record["categoryID"] as? String, let catID = UUID(uuidString: catIDString) {
            expense.categoryID = catID
        }
        expense.createdByDisplayName = record["createdByDisplayName"] as? String
        expense.householdCode = record[householdCodeField] as? String
        if let createdAt = record["createdAt"] as? Date { expense.createdAt = createdAt }
        if let modifiedAt = record[modifiedAtField] as? Date { expense.modifiedAt = modifiedAt }
        if let deletedFlag = record[isSoftDeletedField] as? Int64 {
            expense.isSoftDeleted = deletedFlag != 0
        }
    }

    nonisolated private static func mergeCategory(record: CKRecord, context: NSManagedObjectContext) throws {
        guard let idString = record["id"] as? String, let id = UUID(uuidString: idString) else { return }

        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        let existing = try context.fetch(request).first
        let category = existing ?? Category(context: context)

        category.id = id
        category.name = record["name"] as? String
        category.iconName = record["iconName"] as? String
        category.colorName = record["colorName"] as? String
        if let defaultFlag = record["isDefault"] as? Int64 {
            category.isDefault = defaultFlag != 0
        }
        if let sortOrder = record["sortOrder"] as? Int64 {
            category.sortOrder = Int16(clamping: sortOrder)
        }
        category.householdCode = record[householdCodeField] as? String
        if let modifiedAt = record[modifiedAtField] as? Date { category.modifiedAt = modifiedAt }
        if let deletedFlag = record[isSoftDeletedField] as? Int64 {
            category.isSoftDeleted = deletedFlag != 0
        }
    }

    // MARK: - Backfill on Pair

    /// Uploads every local Expense and Category to the public DB under the current
    /// household code. Used immediately after first pair so the partner sees all
    /// historical records on next fetch, without requiring a manual edit of each row.
    /// No-op if not paired.
    func backfillAllLocalRecords() async {
        guard householdService.isPaired else {
            logger.debug("backfillAllLocalRecords: not paired — skipping")
            return
        }
        let context = persistence.container.viewContext
        let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
        let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()

        do {
            let expenses = try context.fetch(expenseRequest)
            let categories = try context.fetch(categoryRequest)
            logger.info("backfillAllLocalRecords: uploading \(expenses.count) expenses + \(categories.count) categories")
            for expense in expenses { upsert(expense: expense) }
            for category in categories { upsert(category: category) }
        } catch {
            logger.error("backfillAllLocalRecords: fetch FAILED — \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Outbox Persistence + Retry via NWPathMonitor

    private func persistOutboxKeys() {
        let ids = outbox.keys.map { $0.recordName }
        UserDefaults.standard.set(ids, forKey: Self.outboxRecordIDsKey)
    }

    /// On launch, walks the persisted outbox-ID list and rebuilds the CKRecord for each
    /// by looking up the owning Expense/Category in Core Data. Then submits them, so a
    /// mid-outbox app kill doesn't leak pending writes.
    private func restoreOutboxFromPersistence() {
        guard let ids = UserDefaults.standard.stringArray(forKey: Self.outboxRecordIDsKey),
              !ids.isEmpty else { return }
        logger.info("restoreOutboxFromPersistence: restoring \(ids.count) pending records")

        let context = persistence.container.viewContext
        for name in ids {
            guard let uuid = UUID(uuidString: name) else { continue }

            let expenseRequest: NSFetchRequest<Expense> = Expense.fetchRequest()
            expenseRequest.predicate = NSPredicate(format: "id == %@", uuid as NSUUID)
            expenseRequest.fetchLimit = 1
            if let expense = try? context.fetch(expenseRequest).first {
                upsert(expense: expense)
                continue
            }

            let categoryRequest: NSFetchRequest<Category> = Category.fetchRequest()
            categoryRequest.predicate = NSPredicate(format: "id == %@", uuid as NSUUID)
            categoryRequest.fetchLimit = 1
            if let category = try? context.fetch(categoryRequest).first {
                upsert(category: category)
            }
        }
    }

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.scheduleDrainOutbox()
            }
        }
        pathMonitor.start(queue: monitorQueue)
        logger.debug("startPathMonitor: reachability monitor started")
    }

    /// Debounces `drainOutbox()` calls — NWPathMonitor can fire multiple `.satisfied`
    /// events in rapid succession on WiFi join. A 200ms debounce coalesces them into one
    /// drain pass. Also short-circuits if a drain is already in flight.
    private func scheduleDrainOutbox() {
        guard !isDrainingOutbox else { return }
        drainOutboxTask?.cancel()
        drainOutboxTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch { return }
            guard !Task.isCancelled else { return }
            await self.drainOutbox()
        }
    }

    private func drainOutbox() async {
        guard !isDrainingOutbox else { return }
        guard !outbox.isEmpty else { return }
        isDrainingOutbox = true
        defer { isDrainingOutbox = false }

        let snapshot = outbox
        logger.info("drainOutbox: retrying \(snapshot.count) record(s)")
        for (_, record) in snapshot {
            submit(record: record)
        }
    }

    /// Classifies CKError codes as transient (worth retrying from outbox) vs permanent.
    private static func isTransient(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy:
            return true
        default:
            return false
        }
    }

    /// On full unpair: clears the saved fetch cursor so a subsequent re-pair (possibly
    /// with a different code) starts from scratch.
    func resetFetchCursor() {
        UserDefaults.standard.removeObject(forKey: Self.lastFetchDateKey)
        logger.info("resetFetchCursor: lastFetchDate cleared")
    }
}

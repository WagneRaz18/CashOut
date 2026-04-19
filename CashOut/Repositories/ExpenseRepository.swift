@preconcurrency import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "ExpenseRepository")

enum RepositoryError: Error {
    case missingRequiredField(entity: String, field: String)
}

@MainActor
final class ExpenseRepository: ExpenseRepositoryProtocol {
    static let shared = ExpenseRepository()

    private let persistence: PersistenceController
    private let householdService: HouseholdServiceProtocol
    private let publicSync: PublicSyncServiceProtocol

    // MARK: - FRC Observation

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)?
    private var feedFRC: NSFetchedResultsController<Expense>?
    private var frcDelegate: FRCDelegate?

    init(
        persistence: PersistenceController = .shared,
        householdService: HouseholdServiceProtocol = HouseholdService.shared,
        publicSync: PublicSyncServiceProtocol = PublicSyncService.shared
    ) {
        self.persistence = persistence
        self.householdService = householdService
        self.publicSync = publicSync
        logger.debug("ExpenseRepository.init")
    }

    func stopObservingExpenses() {
        feedFRC?.delegate = nil
        feedFRC = nil
        frcDelegate = nil
        onExpensesChanged = nil
        logger.info("stopObservingExpenses: FRC and callback cleared")
    }

    /// Rebuilds the feed FRC with a fresh household-scoped predicate. Call after
    /// `pair()` or `unpair()` so the visible record set reflects the new scope.
    /// Preserves the `onExpensesChanged` callback.
    func reloadObservation() {
        logger.info("reloadObservation: rebuilding FRC for household scope change")
        let savedCallback = onExpensesChanged
        feedFRC?.delegate = nil
        feedFRC = nil
        frcDelegate = nil
        onExpensesChanged = savedCallback
        if savedCallback != nil {
            startObservingExpenses()
        }
    }

    /// Predicate that matches records belonging to the current household:
    /// - `householdCode == currentCode` (records written under this pairing)
    /// - `householdCode == nil` (local records created while unpaired — preserved so
    ///   they don't vanish from the feed when the user first pairs)
    /// - `isSoftDeleted == NO OR nil` (filter out tombstones)
    ///
    /// When the user unpairs, `currentCode == nil`, so the predicate reduces to
    /// `householdCode == nil` and partner records are hidden locally (not deleted;
    /// re-pairing with the same code restores them).
    private func currentHouseholdPredicate() -> NSPredicate {
        let deletedClause = NSPredicate(format: "isSoftDeleted == NO OR isSoftDeleted == nil")
        if let code = householdService.householdCode {
            let scopeClause = NSPredicate(
                format: "householdCode == %@ OR householdCode == nil",
                code
            )
            return NSCompoundPredicate(andPredicateWithSubpredicates: [scopeClause, deletedClause])
        } else {
            let scopeClause = NSPredicate(format: "householdCode == nil")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [scopeClause, deletedClause])
        }
    }

    func startObservingExpenses() {
        assert(onExpensesChanged != nil, "Set onExpensesChanged before calling startObservingExpenses()")

        guard feedFRC == nil else {
            logger.debug("startObservingExpenses: FRC already exists — pushing current data to new subscriber")
            handleFRCUpdate()
            return
        }

        logger.info("startObservingExpenses: creating FRC")

        assert(
            persistence.container.viewContext.automaticallyMergesChangesFromParent,
            "FRC remote-change propagation requires automaticallyMergesChangesFromParent = true"
        )

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        // Scope to current household (or unpaired local records) + filter tombstones.
        request.predicate = currentHouseholdPredicate()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        request.fetchBatchSize = 50

        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: persistence.container.viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        let delegate = FRCDelegate()
        delegate.onChange = { [weak self] in
            logger.debug("FRC controllerDidChangeContent fired")
            self?.handleFRCUpdate()
        }
        frc.delegate = delegate

        self.feedFRC = frc
        self.frcDelegate = delegate

        logger.info("startObservingExpenses: performing initial fetch")
        let fetchStart = CFAbsoluteTimeGetCurrent()
        do {
            try frc.performFetch()
            let elapsed = (CFAbsoluteTimeGetCurrent() - fetchStart) * 1000
            let count = frc.fetchedObjects?.count ?? 0
            logger.info("startObservingExpenses: performFetch completed in \(elapsed, format: .fixed(precision: 1))ms — \(count) objects")
        } catch {
            let elapsed = (CFAbsoluteTimeGetCurrent() - fetchStart) * 1000
            logger.fault("startObservingExpenses: performFetch FAILED in \(elapsed, format: .fixed(precision: 1))ms — \(error.localizedDescription)")
            self.feedFRC?.delegate = nil
            self.feedFRC = nil
            self.frcDelegate = nil
            return
        }
        handleFRCUpdate()
    }

    private func handleFRCUpdate() {
        guard let objects = feedFRC?.fetchedObjects else {
            logger.debug("handleFRCUpdate: no fetchedObjects (FRC not ready)")
            return
        }
        let data = objects.compactMap { expense -> ExpenseData? in
            guard let categoryID = expense.categoryID else { return nil }
            return ExpenseData(
                id: expense.wrappedID,
                amount: expense.amount,
                note: expense.note,
                categoryID: categoryID,
                createdByUserID: expense.wrappedCreatedByUserID,
                createdByDisplayName: expense.wrappedCreatedByDisplayName,
                createdAt: expense.wrappedCreatedAt,
                modifiedAt: expense.wrappedModifiedAt
            )
        }
        let skipped = objects.count - data.count
        if skipped > 0 {
            logger.warning("handleFRCUpdate: \(skipped) expenses skipped (nil categoryID)")
        }
        logger.debug("handleFRCUpdate: publishing \(data.count) expenses to callback")
        onExpensesChanged?(data)
    }

    @MainActor
    private class FRCDelegate: NSObject, @preconcurrency NSFetchedResultsControllerDelegate {
        var onChange: (@MainActor () -> Void)?

        func controllerDidChangeContent(
            _ controller: NSFetchedResultsController<any NSFetchRequestResult>
        ) {
            onChange?()
        }
    }

    func fetchExpenses(for period: DateInterval) async throws -> [ExpenseData] {
        logger.debug("fetchExpenses: \(period.start) — \(period.end)")
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        let periodClause = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            period.start as NSDate,
            period.end as NSDate
        )
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            periodClause,
            currentHouseholdPredicate(),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let results = try persistence.container.viewContext.fetch(request)
        logger.debug("fetchExpenses: found \(results.count) expenses in period")
        return try results.map { expense in
            guard let categoryID = expense.categoryID else {
                throw RepositoryError.missingRequiredField(entity: "Expense", field: "categoryID")
            }
            return ExpenseData(
                id: expense.wrappedID,
                amount: expense.amount,
                note: expense.note,
                categoryID: categoryID,
                createdByUserID: expense.wrappedCreatedByUserID,
                createdByDisplayName: expense.wrappedCreatedByDisplayName,
                createdAt: expense.wrappedCreatedAt,
                modifiedAt: expense.wrappedModifiedAt
            )
        }
    }

    func saveExpense(_ data: ExpenseData) async throws {
        logger.info("saveExpense: id=\(data.id, privacy: .private), amount=\(data.amount, privacy: .private) satang")
        let context = persistence.container.viewContext

        let upsertStart = CFAbsoluteTimeGetCurrent()
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", data.id as NSUUID)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let isNewObject = existing == nil
        let upsertElapsed = (CFAbsoluteTimeGetCurrent() - upsertStart) * 1000
        let expense = existing ?? Expense(context: context)
        logger.debug("saveExpense: upsert fetch in \(upsertElapsed, format: .fixed(precision: 1))ms — \(isNewObject ? "new" : "update")")

        expense.id = data.id
        expense.amount = data.amount
        expense.note = data.note
        expense.categoryID = data.categoryID
        expense.createdByUserID = data.createdByUserID
        expense.createdAt = data.createdAt
        expense.modifiedAt = data.modifiedAt
        expense.isSoftDeleted = false
        // Stamp the record with the current household (may be nil in solo mode — the
        // record stays local-only until pairing, at which point the next save will
        // propagate it to the public DB via publicSync.upsert below).
        expense.householdCode = householdService.householdCode
        // Display name is populated by ExpenseEntryViewModel before calling save for
        // new expenses; preserve any existing value on edits.
        if expense.createdByDisplayName == nil {
            expense.createdByDisplayName = householdService.displayName
        }

        do {
            let contextSaveStart = CFAbsoluteTimeGetCurrent()
            try context.save()
            let contextSaveElapsed = (CFAbsoluteTimeGetCurrent() - contextSaveStart) * 1000
            logger.info("saveExpense: context.save() succeeded in \(contextSaveElapsed, format: .fixed(precision: 1))ms")
        } catch {
            logger.error("saveExpense: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        // Mirror to public CloudKit DB for partner sync. No-op if unpaired.
        if householdService.isPaired {
            publicSync.upsert(expense: expense)
        }
    }

    func deleteExpense(id: UUID) async throws {
        logger.info("deleteExpense: id=\(id)")
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1

        guard let expense = try context.fetch(request).first else {
            logger.warning("deleteExpense: id=\(id) not found — already deleted")
            return
        }

        // Soft-delete: tombstone the record so the partner sees the deletion. The
        // public DB has no native tombstones, so we mirror an `isSoftDeleted = true`
        // record and let the FRC predicate filter it from the UI.
        expense.isSoftDeleted = true
        expense.modifiedAt = Date()
        do {
            try context.save()
            logger.info("deleteExpense: tombstoned successfully")
        } catch {
            logger.error("deleteExpense: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        if householdService.isPaired {
            publicSync.upsert(expense: expense)
        }
    }
}

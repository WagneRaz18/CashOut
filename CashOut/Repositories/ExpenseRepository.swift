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
    private let cloudSharingService: CloudSharingServiceProtocol?

    // MARK: - FRC Observation (Story 2-1)

    var onExpensesChanged: (@MainActor ([ExpenseData]) -> Void)?
    private var feedFRC: NSFetchedResultsController<Expense>?
    private var frcDelegate: FRCDelegate?

    init(
        persistence: PersistenceController = .shared,
        cloudSharingService: CloudSharingServiceProtocol? = CloudSharingService.shared
    ) {
        self.persistence = persistence
        self.cloudSharingService = cloudSharingService
        logger.debug("ExpenseRepository.init")
    }

    func stopObservingExpenses() {
        feedFRC?.delegate = nil
        feedFRC = nil
        frcDelegate = nil
        onExpensesChanged = nil
        logger.info("stopObservingExpenses: FRC and callback cleared")
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
            // Tear down so a future call can retry from scratch
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

    // MARK: - FRC Delegate (nested class for NSObject conformance)

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
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            period.start as NSDate,
            period.end as NSDate
        )
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
        request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
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

        // PRE-SAVE: Route to shared store if participant (new objects only)
        if isNewObject {
            cloudSharingService?.prepareObjectForSharedSave(expense)
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

    }

    func shareNewExpenseToHousehold(id: UUID) async {
        logger.info("shareNewExpenseToHousehold: starting — id=\(id, privacy: .private)")
        let totalStart = CFAbsoluteTimeGetCurrent()
        let context = persistence.container.viewContext
        let refetchStart = CFAbsoluteTimeGetCurrent()
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        let expense: Expense
        do {
            guard let found = try context.fetch(request).first else {
                logger.warning("shareNewExpenseToHousehold: expense \(id, privacy: .private) not found — skipping")
                return
            }
            expense = found
            let refetchElapsed = (CFAbsoluteTimeGetCurrent() - refetchStart) * 1000
            logger.debug("shareNewExpenseToHousehold: re-fetch in \(refetchElapsed, format: .fixed(precision: 1))ms")
        } catch {
            logger.fault("shareNewExpenseToHousehold: fetch FAILED — \(error.localizedDescription, privacy: .public)")
            return
        }
        guard !Task.isCancelled else { return }
        logger.debug("shareNewExpenseToHousehold: sharing to household")
        do {
            try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([expense])
        } catch {
            logger.error("shareNewExpenseToHousehold: FAILED — \(error.localizedDescription)")
        }
        let totalElapsed = (CFAbsoluteTimeGetCurrent() - totalStart) * 1000
        logger.info("shareNewExpenseToHousehold: completed in \(totalElapsed, format: .fixed(precision: 1))ms")
    }

    func deleteExpense(id: UUID) async throws {
        logger.info("deleteExpense: id=\(id)")
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let expense = try context.fetch(request).first else {
            logger.warning("deleteExpense: not found in store — already deleted?")
            return
        }
        context.delete(expense)
        do {
            try context.save()
            logger.info("deleteExpense: success")
        } catch {
            logger.error("deleteExpense: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }
    }
}

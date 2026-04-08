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

    func startObservingExpenses() {
        guard feedFRC == nil else {
            logger.debug("startObservingExpenses: FRC already exists — skipped")
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
        logger.info("saveExpense: id=\(data.id), amount=\(data.amount) satang")
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let isNewObject = existing == nil
        let expense = existing ?? Expense(context: context)
        logger.debug("saveExpense: \(isNewObject ? "new" : "update")")

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
            try context.save()
            logger.info("saveExpense: context.save() succeeded")
        } catch {
            logger.error("saveExpense: context.save() FAILED — \(error.localizedDescription)")
            context.rollback()
            throw error
        }

        // POST-SAVE: Move to shared zone if owner (new objects only)
        // Fire-and-forget: each share is independent — do NOT cancel previous shares,
        // as each targets a different object and must complete for partner visibility.
        if isNewObject {
            let sharingService = cloudSharingService
            let objectID = expense.objectID
            Task { @MainActor in
                do {
                    let object = context.object(with: objectID)
                    logger.debug("saveExpense: sharing to household (background, new object)")
                    try await sharingService?.shareObjectsToHouseholdIfNeeded([object])
                    guard !Task.isCancelled else { return }
                } catch {
                    logger.error("saveExpense: sharing FAILED — \(error.localizedDescription)")
                }
            }
        }
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

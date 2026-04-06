@preconcurrency import CoreData
import os

enum RepositoryError: Error {
    case missingRequiredField(entity: String, field: String)
}

@MainActor
final class ExpenseRepository: ExpenseRepositoryProtocol {
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
    }

    func startObservingExpenses() {
        guard feedFRC == nil else { return }

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
            self?.handleFRCUpdate()
        }
        frc.delegate = delegate

        self.feedFRC = frc
        self.frcDelegate = delegate

        do {
            try frc.performFetch()
        } catch {
            os_log(.fault, "ExpenseRepository: FRC performFetch failed — %{public}@", error.localizedDescription)
        }
        handleFRCUpdate()
    }

    private func handleFRCUpdate() {
        guard let objects = feedFRC?.fetchedObjects else { return }
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
        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(
            format: "createdAt >= %@ AND createdAt < %@",
            period.start as NSDate,
            period.end as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let results = try persistence.container.viewContext.fetch(request)
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
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", data.id as CVarArg)
        request.fetchLimit = 1

        let existing = try context.fetch(request).first
        let isNewObject = existing == nil
        let expense = existing ?? Expense(context: context)

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
        } catch {
            context.rollback()
            throw error
        }

        // POST-SAVE: Move to shared zone if owner (new objects only)
        if isNewObject {
            try await cloudSharingService?.shareObjectsToHouseholdIfNeeded([expense])
        }
    }

    func deleteExpense(id: UUID) async throws {
        let context = persistence.container.viewContext

        let request: NSFetchRequest<Expense> = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let expense = try context.fetch(request).first else { return }
        context.delete(expense)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

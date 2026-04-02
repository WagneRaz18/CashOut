import Foundation

@MainActor
@Observable
final class FeedViewModel {

    // MARK: - Observable Properties

    var expenses: [ExpenseData] = []
    var categories: [CategoryData] = []
    var errorMessage: String?

    var isEmpty: Bool { expenses.isEmpty }

    // MARK: - Dependencies

    @ObservationIgnored
    private var repository: ExpenseRepositoryProtocol

    @ObservationIgnored
    private let categoryRepository: CategoryRepositoryProtocol

    @ObservationIgnored
    private let authService: AuthenticationServiceProtocol

    @ObservationIgnored
    private var isObserving = false

    @ObservationIgnored
    private var categoryTask: Task<Void, Never>?

    // MARK: - Init

    init(
        repository: ExpenseRepositoryProtocol = ExpenseRepository(),
        categoryRepository: CategoryRepositoryProtocol = CategoryRepository(),
        authService: AuthenticationServiceProtocol = AuthenticationService()
    ) {
        self.repository = repository
        self.categoryRepository = categoryRepository
        self.authService = authService
    }

    // MARK: - Observation

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true

        repository.onExpensesChanged = { [weak self] expenses in
            self?.expenses = expenses
            self?.reloadCategories()
        }
        repository.startObservingExpenses()
    }

    // MARK: - Category Lookup

    func categoryFor(_ expense: ExpenseData) -> CategoryData? {
        categories.first { $0.id == expense.categoryID }
    }

    // MARK: - Partner Attribution

    func isCurrentUser(_ expense: ExpenseData) -> Bool {
        // Treat unattributed expenses (empty createdByUserID) as current user's
        guard !expense.createdByUserID.isEmpty else { return true }
        guard let currentUserID = authService.currentUserID else { return true }
        return expense.createdByUserID == currentUserID
    }

    func partnerInitials(for expense: ExpenseData) -> String {
        isCurrentUser(expense) ? "Me" : "P"
    }

    // MARK: - Private

    private func reloadCategories() {
        categoryTask?.cancel()
        categoryTask = Task {
            do {
                let fetched = try await categoryRepository.fetchCategories()
                guard !Task.isCancelled else { return }
                categories = fetched
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

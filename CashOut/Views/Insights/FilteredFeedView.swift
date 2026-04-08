import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FilteredFeedView")

struct FilteredFeedView: View {
    let categoryID: UUID
    let categoryName: String
    let period: DateInterval
    let categories: [CategoryData]
    let currentUserID: String?
    let repository: ExpenseRepositoryProtocol

    @State private var expenses: [ExpenseData] = []
    @State private var errorMessage: String?

    init(
        categoryID: UUID,
        categoryName: String,
        period: DateInterval,
        categories: [CategoryData],
        currentUserID: String?,
        repository: ExpenseRepositoryProtocol = ExpenseRepository.shared
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.period = period
        self.categories = categories
        self.currentUserID = currentUserID
        self.repository = repository
    }

    var body: some View {
        Group {
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if expenses.isEmpty {
                Text("No \(categoryName) entries this period")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(expenses) { expense in
                        FeedRowView(
                            expense: expense,
                            category: categories.first { $0.id == expense.categoryID },
                            isCurrentUser: isCurrentUser(expense),
                            partnerInitials: partnerInitials(for: expense)
                        )
                    }
                }
            }
        }
        .navigationTitle(categoryName)
        .task(id: categoryID) {
            logger.info("FilteredFeedView.task: fetching expenses for category \(categoryID, privacy: .private) (\(categoryName, privacy: .private))")
            do {
                let all = try await repository.fetchExpenses(for: period)
                guard !Task.isCancelled else { return }
                expenses = all.filter { $0.categoryID == categoryID }
                logger.info("FilteredFeedView: showing \(expenses.count) of \(all.count) expenses for category")
            } catch {
                guard !Task.isCancelled else { return }
                logger.error("FilteredFeedView: fetch failed — \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Helpers

    private func isCurrentUser(_ expense: ExpenseData) -> Bool {
        guard let currentUserID else { return true }
        return expense.createdByUserID == currentUserID
    }

    private func partnerInitials(for expense: ExpenseData) -> String {
        isCurrentUser(expense) ? "Me" : "P"
    }
}

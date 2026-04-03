import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var expenseToEdit: ExpenseData?

    var body: some View {
        Group {
            if viewModel.isEmpty {
                Text("No entries yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.expenses) { expense in
                        Button {
                            expenseToEdit = expense
                        } label: {
                            FeedRowView(
                                expense: expense,
                                category: viewModel.categoryFor(expense),
                                isCurrentUser: viewModel.isCurrentUser(expense),
                                partnerInitials: viewModel.partnerInitials(for: expense)
                            )
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                Task {
                                    await viewModel.deleteExpense(expense)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                expenseToEdit = expense
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .sheet(item: $expenseToEdit) { expense in
            EditExpenseSheet(expense: expense, onSaveComplete: {
                expenseToEdit = nil
            })
            .presentationDetents([.large])
        }
        .navigationTitle("Feed")
        .onAppear {
            viewModel.startObserving()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

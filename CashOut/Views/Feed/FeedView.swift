import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FeedView")

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var expenseToEdit: ExpenseData?
    @State private var showSettings = false

    var body: some View {
        Group {
            if viewModel.isEmpty {
                Text("No entries yet")
                    .font(.body)
                    .foregroundStyle(SemanticColor.onSurfaceVariant)
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
                        .listRowBackground(Surface.containerLow)
                        .listRowSeparator(.hidden)
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
                            .tint(SemanticColor.primary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Surface.base)
            }
        }
        .sheet(item: $expenseToEdit) { expense in
            logger.info("Edit sheet presented for expense id=\(expense.id)")
            EditExpenseSheet(expense: expense, onSaveComplete: {
                logger.info("Edit sheet dismissed after save")
                expenseToEdit = nil
            })
            .presentationDetents([.large])
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if viewModel.syncStatus == .noICloudAccount {
                    ICloudBannerView()
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SemanticColor.error)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                }
            }
        }
        .navigationTitle("Feed")
        .toolbar {
            if viewModel.syncStatus == .syncFailure {
                ToolbarItem(placement: .topBarLeading) {
                    SyncStatusIndicator(syncStatus: viewModel.syncStatus)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear {
            logger.debug("FeedView.onAppear — starting observation")
            viewModel.startObserving()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

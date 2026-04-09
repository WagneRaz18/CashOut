import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FeedView")

struct FeedView: View {
    @State private var viewModel = FeedViewModel()
    @State private var expenseToEdit: ExpenseData?
    @State private var expenseToDelete: ExpenseData?
    @State private var deleteTask: Task<Void, Never>?
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
                        .accessibilityHint("Double tap to edit")
                        .listRowBackground(Surface.containerLow)
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(SemanticColor.outlineVariant)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                logger.info("Delete swiped for expense id=\(expense.id, privacy: .private)")
                                expenseToDelete = expense
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Surface.base)
            }
        }
        .sheet(item: $expenseToEdit) { expense in
            EditExpenseSheet(expense: expense, onSaveComplete: {
                logger.info("Edit sheet dismissed after save")
                expenseToEdit = nil
            })
            .presentationDetents([.large])
            .onAppear { logger.info("Edit sheet presented for expense id=\(expense.id, privacy: .private)") }
        }
        .confirmationDialog(
            "Delete expense?",
            isPresented: Binding(
                get: { expenseToDelete != nil },
                set: { if !$0 { expenseToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: expenseToDelete
        ) { expense in
            Button("Delete", role: .destructive) {
                logger.info("Delete confirmed for expense id=\(expense.id, privacy: .private)")
                deleteTask?.cancel()
                deleteTask = Task { await viewModel.deleteExpense(expense) }
            }
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
                .onAppear { logger.debug("Navigating to Settings from Feed") }
        }
        .onAppear {
            logger.debug("FeedView.onAppear — starting observation")
            viewModel.startObserving()
        }
        .onDisappear {
            logger.debug("FeedView.onDisappear — cancelling tasks")
            deleteTask?.cancel()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

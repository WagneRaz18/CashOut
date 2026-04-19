import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "FeedView")

struct FeedView: View {
    // Owned by ContentView — iOS 26 value-based `Tab` API re-evaluates content
    // closures on `selectedTab` change and tears down child `@State` storage,
    // recreating the ViewModel on every tab switch. Lifting to ContentView
    // preserves the ViewModel (and its FRC subscription) across tab switches.
    @Bindable var viewModel: FeedViewModel
    @State private var expenseToEdit: ExpenseData?
    @State private var showSettings = false
    @State private var deleteTask: Task<Void, Never>?

    var body: some View {
        List {
            ForEach(viewModel.groupedExpenses) { section in
                Section {
                    ForEach(section.expenses) { expense in
                        let isFirst = expense.id == section.expenses.first?.id
                        let isLast = expense.id == section.expenses.last?.id
                        let radius: CGFloat = 16
                        let shape = UnevenRoundedRectangle(
                            topLeadingRadius: isFirst ? radius : 0,
                            bottomLeadingRadius: isLast ? radius : 0,
                            bottomTrailingRadius: isLast ? radius : 0,
                            topTrailingRadius: isFirst ? radius : 0,
                            style: .continuous
                        )

                        Button {
                            expenseToEdit = expense
                        } label: {
                            FeedRowView(
                                expense: expense,
                                category: viewModel.categoryFor(expense),
                                isCurrentUser: viewModel.isCurrentUser(expense),
                                partnerInitials: viewModel.partnerInitials(for: expense)
                            )
                            .padding(.vertical, Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Surface.containerLow)
                            .clipShape(shape)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double tap to edit")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(
                            top: isFirst ? Spacing.xs : 0.5,
                            leading: Spacing.md,
                            bottom: isLast ? Spacing.xs : 0.5,
                            trailing: Spacing.md
                        ))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                logger.info("Delete confirmed for expense id=\(expense.id, privacy: .private)")
                                deleteTask = Task { await viewModel.deleteExpense(expense) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(SemanticColor.onSurfaceVariant.opacity(0.7))
                        .listRowInsets(EdgeInsets(
                            top: 0, leading: Spacing.md,
                            bottom: 0, trailing: Spacing.md
                        ))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Surface.base)
        .refreshable {
            await viewModel.refresh()
        }
        .overlay {
            if viewModel.isEmpty {
                ContentUnavailableView("No entries yet", systemImage: "tray")
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
        .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
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
        .sheet(item: $expenseToEdit) { expense in
            EditExpenseSheet(expense: expense, onSaveComplete: {
                logger.info("Edit sheet dismissed after save")
                expenseToEdit = nil
            })
            .presentationDetents([.large])
            .onAppear { logger.info("Edit sheet presented for expense id=\(expense.id, privacy: .private)") }
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
                .onAppear { logger.debug("Navigating to Settings from Feed") }
        }
        .task {
            logger.debug("FeedView.task — starting observation")
            viewModel.startObserving()
        }
        .onDisappear {
            logger.debug("FeedView.onDisappear")
            deleteTask?.cancel()
        }
    }
}

// Preview isolates the data layer via PersistenceController.preview (in-memory).
// Service-layer deps (cloudSharingService, syncMonitorService) still default to .shared
// because FeedViewModel requires non-optional instances; full mock isolation would need
// per-protocol test doubles in the main target.
#Preview {
    NavigationStack {
        FeedView(viewModel: FeedViewModel(
            repository: ExpenseRepository(persistence: .preview),
            categoryRepository: CategoryRepository(persistence: .preview)
        ))
    }
}

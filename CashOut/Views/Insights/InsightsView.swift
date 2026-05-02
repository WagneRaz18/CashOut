import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "InsightsView")

struct InsightsView: View {
    // Owned by ContentView — iOS 26 value-based `Tab` API re-evaluates content
    // closures on `selectedTab` change and tears down child `@State` storage,
    // recreating the ViewModel on every tab switch. Lifting to ContentView
    // preserves the ViewModel (and cached period data) across tab switches.
    @Bindable var viewModel: InsightsViewModel
    @State private var showSettings = false

    private var periodBinding: Binding<InsightsViewModel.TimePeriod> {
        Binding(
            get: { viewModel.selectedPeriod },
            set: { newPeriod in viewModel.dateOffset = 0; viewModel.selectedPeriod = newPeriod }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: periodBinding) {
                ForEach(InsightsViewModel.TimePeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            if viewModel.syncStatus == .noICloudAccount {
                ICloudBannerView()
            }

            ScrollView {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(SemanticColor.error)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                }

                if viewModel.isEmpty && viewModel.selectedPeriod != .monthly {
                    InsightsSummaryView(
                        slices: [],
                        headlineText: viewModel.headlineText,
                        periodLabel: viewModel.periodLabel,
                        comparisonText: nil,
                        emptyStateText: viewModel.emptyStateText,
                        accessibilityLabel: viewModel.chartAccessibilityLabel,
                        onSliceTapped: { _ in }
                    )
                    .containerRelativeFrame(.vertical) { height, _ in
                        height
                    }
                } else {
                    VStack(spacing: Spacing.md) {
                        InsightsSummaryView(
                            slices: viewModel.chartSlices,
                            headlineText: viewModel.headlineText,
                            periodLabel: viewModel.periodLabel,
                            comparisonText: viewModel.comparisonText,
                            emptyStateText: viewModel.emptyStateText,
                            accessibilityLabel: viewModel.chartAccessibilityLabel,
                            onSliceTapped: { categoryID in
                                viewModel.selectCategory(categoryID)
                            }
                        )

                        if viewModel.selectedPeriod == .monthly {
                            MonthlyCalendarView(
                                calendarMonth: viewModel.viewedMonthStart,
                                dailyTotals: viewModel.dailyTotals,
                                today: Date(),
                                onDayTap: { date in viewModel.navigateToDay(date) }
                            )
                            .transition(.opacity)
                        } else {
                            DailyBarChartView(
                                entries: viewModel.barEntries,
                                accessibilityLabel: viewModel.barChartAccessibilityLabel
                            )
                            .transition(.opacity)
                        }

                        if !viewModel.isEmpty {
                            CategoryBreakdownView(
                                slices: viewModel.chartSlices,
                                totalAmount: viewModel.totalAmount,
                                onCategoryTapped: { categoryID in
                                    viewModel.selectCategory(categoryID)
                                }
                            )
                        }
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 {
                            viewModel.navigatePrevious()
                        } else {
                            viewModel.navigateNext()
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.15), value: viewModel.loadKey)
        }
        .background(Surface.base)
        .navigationTitle("Insights")
        .navigationDestination(item: Bindable(viewModel).selectedDestination) { destination in
            FilteredFeedView(
                categoryID: destination.categoryID,
                categoryName: viewModel.chartSlices.first { $0.categoryID == destination.categoryID }?.categoryName ?? "Category",
                period: destination.interval,
                categories: viewModel.fetchedCategories,
                currentUserID: viewModel.currentUserID
            )
        }
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
                .onAppear { logger.debug("Navigating to Settings from Insights") }
        }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: viewModel.navigateNext()
            case .decrement: viewModel.navigatePrevious()
            @unknown default: break
            }
        }
        .task(id: viewModel.loadKey) {
            logger.info("InsightsView.task: loading period=\(viewModel.selectedPeriod.rawValue, privacy: .public) offset=\(viewModel.dateOffset, privacy: .public)")
            await viewModel.loadData()
        }
        .task {
            logger.debug("InsightsView.task: subscribing to remote changes")
            await viewModel.subscribeToRemoteChanges()
        }
    }
}

// Preview isolates the data layer via PersistenceController.preview (in-memory).
// Service-layer deps (syncMonitorService, authService) still default to .shared.
#Preview {
    NavigationStack {
        InsightsView(viewModel: InsightsViewModel(
            repository: ExpenseRepository(persistence: .preview),
            categoryRepository: CategoryRepository(persistence: .preview)
        ))
    }
}

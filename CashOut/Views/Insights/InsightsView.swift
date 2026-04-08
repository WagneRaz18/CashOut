import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "InsightsView")

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: Bindable(viewModel).selectedPeriod) {
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

                if viewModel.isEmpty {
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

                        DailyBarChartView(
                            entries: viewModel.barEntries,
                            accessibilityLabel: viewModel.barChartAccessibilityLabel
                        )

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
        .task(id: viewModel.selectedPeriod) {
            logger.info("InsightsView.task: loading data for period \(viewModel.selectedPeriod.rawValue)")
            await viewModel.loadData()
        }
        .task {
            logger.debug("InsightsView.task: subscribing to remote changes")
            await viewModel.subscribeToRemoteChanges()
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
}

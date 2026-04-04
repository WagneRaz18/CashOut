import SwiftUI

struct InsightsView: View {
    @State private var viewModel = InsightsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            Picker("Period", selection: $viewModel.selectedPeriod) {
                ForEach(InsightsViewModel.TimePeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)

            ScrollView {
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
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

                        // Placeholder for bar chart and category breakdown (Story 3-3)
                    }
                }
            }
            .navigationDestination(item: Bindable(viewModel).selectedCategoryID) { categoryID in
                FilteredFeedView(
                    categoryID: categoryID,
                    categoryName: viewModel.chartSlices.first { $0.categoryID == categoryID }?.categoryName ?? "Category",
                    period: viewModel.currentPeriodInterval ?? DateInterval(),
                    categories: viewModel.fetchedCategories,
                    currentUserID: viewModel.currentUserID
                )
            }
        }
        .navigationTitle("Insights")
        .task(id: viewModel.selectedPeriod) {
            await viewModel.loadData()
        }
        .task {
            await viewModel.subscribeToRemoteChanges()
        }
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
}

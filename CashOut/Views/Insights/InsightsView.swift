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
                    VStack(spacing: Spacing.sm) {
                        Text(viewModel.headlineText)
                            .font(.title3)
                            .monospacedDigit()

                        Text(viewModel.emptyStateText)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .frame(maxWidth: .infinity)
                    .containerRelativeFrame(.vertical) { height, _ in
                        height
                    }
                } else {
                    VStack(spacing: Spacing.md) {
                        VStack(spacing: Spacing.xs) {
                            Text(viewModel.headlineText)
                                .font(.title3)
                                .monospacedDigit()

                            Text(viewModel.periodLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let comparison = viewModel.comparisonText {
                                Text(comparison)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .frame(maxWidth: .infinity)
                        .padding(.top, Spacing.md)

                        // Placeholder for donut chart (Story 3-2)
                        // Placeholder for bar chart and category breakdown (Story 3-3)
                    }
                }
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

import SwiftUI
import Charts

struct InsightsSummaryView: View {
    let slices: [InsightsViewModel.ChartSlice]
    let headlineText: String
    let periodLabel: String
    let comparisonText: String?
    let emptyStateText: String
    let accessibilityLabel: String
    let onSliceTapped: (UUID) -> Void

    @State private var selectedAngle: Int64?

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            donutChart
            headlineGroup
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.md)
    }

    // MARK: - Donut Chart

    private var donutChart: some View {
        Group {
            if slices.isEmpty {
                emptyDonut
            } else {
                populatedDonut
            }
        }
        .frame(width: 120, height: 120)
    }

    private var populatedDonut: some View {
        Chart {
            ForEach(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.total),
                    innerRadius: .ratio(0.618),
                    angularInset: 1
                )
                .cornerRadius(3)
                .foregroundStyle(by: .value("Category", "\(slice.categoryID)_\(slice.categoryName)"))
                .accessibilityLabel(slice.categoryName)
                .accessibilityValue(slice.total.displayAmount)
            }
        }
        .chartForegroundStyleScale(
            domain: slices.map { "\($0.categoryID)_\($0.categoryName)" },
            range: slices.map { Color($0.colorName) }
        )
        .chartLegend(.hidden)
        .chartAngleSelection(value: $selectedAngle)
        .chartGesture { chart in
            SpatialTapGesture()
                .onEnded { event in
                    let angle = chart.angle(at: event.location)
                    chart.selectAngleValue(at: angle)
                }
        }
        .onChange(of: selectedAngle) { _, newValue in
            guard let rawValue = newValue else { return }
            if let categoryID = resolveCategory(for: rawValue) {
                onSliceTapped(categoryID)
            }
            selectedAngle = nil
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var emptyDonut: some View {
        Chart {
            SectorMark(
                angle: .value("Empty", 1),
                innerRadius: .ratio(0.618)
            )
            .foregroundStyle(Color.secondary.opacity(0.2))
        }
        .chartLegend(.hidden)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Headline Group

    private var headlineGroup: some View {
        Group {
            if slices.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(headlineText)
                        .font(.title3)
                        .monospacedDigit()

                    Text(emptyStateText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(headlineText)
                        .font(.title3)
                        .monospacedDigit()

                    Text(periodLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let comparison = comparisonText {
                        Text(comparison)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func resolveCategory(for rawValue: Int64) -> UUID? {
        var accumulated: Int64 = 0
        for slice in slices {
            accumulated += slice.total
            if rawValue <= accumulated {
                return slice.categoryID
            }
        }
        return slices.last?.categoryID
    }
}

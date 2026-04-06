import SwiftUI
import Charts

struct DailyBarChartView: View {
    let entries: [InsightsViewModel.BarEntry]
    let accessibilityLabel: String

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            Chart {
                ForEach(entries) { entry in
                    BarMark(
                        x: .value("Period", entry.label),
                        y: .value("Amount", entry.total)
                    )
                    .foregroundStyle(SemanticColor.primary.opacity(0.7))
                    .cornerRadius(4)
                    .accessibilityLabel(entry.label)
                    .accessibilityValue(entry.total.displayAmount)
                }
            }
            .chartXScale(domain: entries.map(\.label))
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 140)
            .padding(.horizontal, Spacing.md)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

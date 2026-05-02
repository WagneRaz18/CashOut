import SwiftUI
import Charts

struct DailyBarChartView: View {
    let entries: [InsightsViewModel.BarEntry]
    let accessibilityLabel: String

    private var datesByLabel: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.compactMap { entry in
            entry.dateLabel.map { (entry.label, $0) }
        })
    }

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
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            if let dateLabel = datesByLabel[label] {
                                VStack(spacing: 1) {
                                    Text(label)
                                    Text(dateLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text(label)
                            }
                        }
                    }
                }
            }
            .chartYScale(domain: 0...Swift.max(1, entries.map(\.total).max() ?? 1))
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 140)
            .padding(.horizontal, Spacing.md)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

import SwiftUI

struct MonthlyCalendarView: View {
    let calendarMonth: Date
    let dailyTotals: [Date: Int64]
    let today: Date
    let onDayTap: (Date) -> Void

    private static let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 1), count: 7)

    @State private var cells: [MonthGridCell] = []

    private var todayStart: Date {
        Calendar.gregorian.startOfDay(for: today)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(Self.weekdaySymbols.indices, id: \.self) { i in
                    Text(Self.weekdaySymbols[i])
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(Calendar.gregorian.weekdaySymbols[i])
                }
            }
            .padding(.horizontal, Spacing.sm)

            LazyVGrid(columns: Self.columns, spacing: 1) {
                ForEach(cells) { cell in
                    if let date = cell.date {
                        let dateStart = Calendar.gregorian.startOfDay(for: date)
                        CalendarDayCell(
                            date: date,
                            amount: dailyTotals[dateStart],
                            isToday: dateStart == todayStart,
                            isFuture: dateStart > todayStart,
                            onTap: { onDayTap(date) }
                        )
                    } else {
                        Color.clear
                            .aspectRatio(0.75, contentMode: .fit)
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .padding(.vertical, Spacing.sm)
        .onChange(of: calendarMonth, initial: true) { _, _ in cells = buildCells() }
    }

    private func buildCells() -> [MonthGridCell] {
        guard let range = Calendar.gregorian.range(of: .day, in: .month, for: calendarMonth),
              let firstDay = Calendar.gregorian.date(
                  from: Calendar.gregorian.dateComponents([.year, .month], from: calendarMonth)
              ) else {
            return []
        }
        let weekdayOffset = Calendar.gregorian.component(.weekday, from: firstDay) - 1
        var cells: [MonthGridCell] = (0..<weekdayOffset).map {
            MonthGridCell(id: -($0 + 1), date: nil)
        }
        for day in range {
            if let date = Calendar.gregorian.date(byAdding: .day, value: day - 1, to: firstDay) {
                cells.append(MonthGridCell(id: Calendar.gregorian.ordinality(of: .day, in: .era, for: date) ?? 0, date: date))
            }
        }
        return cells
    }
}

private struct MonthGridCell: Identifiable {
    let id: Int
    let date: Date?
}

@MainActor
private struct CalendarDayCell: View {
    let date: Date
    let amount: Int64?
    let isToday: Bool
    let isFuture: Bool
    let onTap: () -> Void

    @ScaledMetric(relativeTo: .caption2) private var amountFontSize: CGFloat = 8

    private static let a11yFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .none
        return fmt
    }()

    var body: some View {
        VStack(spacing: 1) {
            ZStack {
                if isToday {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 22, height: 22)
                }
                Text("\(Calendar.gregorian.component(.day, from: date))")
                    .font(.caption2)
                    .fontWeight(isToday ? .semibold : .regular)
                    .foregroundStyle(isToday ? Color.white : isFuture ? Color.secondary : Color.primary)
            }

            if let amount, amount > 0 {
                Text(amount.displayAmount)
                    .font(.system(size: amountFontSize))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Spacer().frame(height: 9)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.75, contentMode: .fit)
        .contentShape(Rectangle())
        .opacity(isFuture ? 0.3 : 1.0)
        .allowsHitTesting(!isFuture)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isFuture ? "Future date, not available" : "Double-tap to navigate to this day")
        .accessibilityAddTraits(isFuture ? [] : .isButton)
        .onTapGesture { onTap() }
    }

    private var accessibilityLabel: String {
        let dateStr = Self.a11yFormatter.string(from: date)
        if let amount, amount > 0 {
            return "\(dateStr), \(amount.displayAmount)"
        }
        return dateStr
    }
}

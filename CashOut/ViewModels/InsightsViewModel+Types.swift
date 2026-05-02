import Foundation

extension InsightsViewModel {

    enum TimePeriod: String, CaseIterable {
        case daily = "Day"
        case weekly = "Week"
        case monthly = "Month"

        var currentPeriodLabel: String {
            switch self {
            case .daily: "Today"
            case .weekly: "This Week"
            case .monthly: "This Month"
            }
        }

        var previousPeriodLabel: String {
            switch self {
            case .daily: "yesterday"
            case .weekly: "last week"
            case .monthly: "last month"
            }
        }

        var emptyStateLabel: String {
            switch self {
            case .daily: "day"
            case .weekly: "week"
            case .monthly: "month"
            }
        }

        var calendarComponent: Calendar.Component {
            switch self {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            }
        }
    }

    struct CategoryTotal: Identifiable, Sendable {
        let categoryID: UUID
        let total: Int64
        var id: UUID { categoryID }
    }

    struct ChartSlice: Identifiable, Sendable {
        let categoryID: UUID
        let categoryName: String
        let colorName: String
        let iconName: String
        let total: Int64
        var id: UUID { categoryID }
    }

    struct BarEntry: Identifiable, Sendable {
        let position: Int
        let label: String
        let dateLabel: String?
        let total: Int64
        var id: Int { position }

        init(position: Int, label: String, total: Int64, dateLabel: String? = nil) {
            self.position = position
            self.label = label
            self.dateLabel = dateLabel
            self.total = total
        }
    }

    struct CategoryNavDestination: Hashable {
        let categoryID: UUID
        let interval: DateInterval
    }
}

import SwiftUI

struct FeedRowView: View {
    let expense: ExpenseData
    let category: CategoryData?
    let isCurrentUser: Bool
    let partnerInitials: String

    @Environment(\.colorScheme) private var colorScheme

    @ScaledMetric(relativeTo: .body) private var badgeSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var badgeIconSize: CGFloat = 14
    @ScaledMetric(relativeTo: .caption2) private var partnerCircleSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var partnerFontSize: CGFloat = 10

    private static let maxNoteLength = 20

    private var truncatedNote: String? {
        guard let note = expense.note, !note.isEmpty else { return nil }
        let singleLine = note.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= Self.maxNoteLength {
            return singleLine
        }
        return String(singleLine.prefix(Self.maxNoteLength - 2)) + ".."
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Leading: category icon in colored circle badge (28×28pt)
            categoryBadge

            // Center: category name + partner initials + timestamp
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(category?.name ?? "Unknown")
                    .font(.body)
                    .foregroundStyle(SemanticColor.onSurface)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    partnerCircle
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        Text(expense.createdAt.relativeFormatted(relativeTo: context.date))
                            .font(.caption)
                            .foregroundStyle(SemanticColor.onSurfaceVariant)
                            .monospacedDigit()
                    }
                }
            }

            noteChip

            Spacer()

            // Trailing: amount
            Text(expense.amount.displayAmount)
                .font(.system(.body, design: .monospaced).monospacedDigit())
                .foregroundStyle(SemanticColor.onSurface)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        // VoiceOver reads the label once when a row gains focus; using the live `Date()` shim here
        // (not the TimelineView context) gives a fresh snapshot at that moment without triggering
        // per-tick a11y announcements.
        var label = "\(partnerInitials) spent \(expense.amount.displayAmount) on \(category?.name ?? "unknown"), \(expense.createdAt.relativeFormatted)"
        if let note = expense.note, !note.isEmpty {
            label += ", note: \(note)"
        }
        return label
    }

    // MARK: - Subviews

    @ViewBuilder
    private var noteChip: some View {
        if let noteText = truncatedNote {
            Text(noteText)
                .font(.caption2)
                .foregroundStyle(SemanticColor.onSurfaceVariant)
                .lineLimit(1)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, 2)
                .background(
                    SemanticColor.secondaryContainer,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .frame(maxWidth: 100)
        }
    }

    private var categoryBadge: some View {
        let color = CategoryColor(from: category?.colorName ?? "CoolGray")?.color ?? .gray
        return Image(systemName: category?.iconName ?? "ellipsis.circle.fill")
            .font(.system(size: badgeIconSize))
            .foregroundStyle(.white)
            .frame(width: badgeSize, height: badgeSize)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var partnerCircle: some View {
        let color = PartnerColor.color(isCurrentUser: isCurrentUser, colorScheme: colorScheme)
        return Text(partnerInitials)
            .font(.system(size: partnerFontSize, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: partnerCircleSize, height: partnerCircleSize)
            .background(color, in: Circle())
    }
}

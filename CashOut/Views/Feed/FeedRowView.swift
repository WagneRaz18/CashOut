import SwiftUI

struct FeedRowView: View {
    let expense: ExpenseData
    let category: CategoryData?
    let isCurrentUser: Bool
    let partnerInitials: String

    @Environment(\.colorScheme) private var colorScheme

    private static let maxNoteLength = 30

    private var truncatedNote: String? {
        guard let note = expense.note, !note.isEmpty else { return nil }
        let singleLine = note.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count <= Self.maxNoteLength {
            return singleLine
        }
        return String(singleLine.prefix(Self.maxNoteLength - 2)) + ".."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Note text (only shown when note exists)
            if let noteText = truncatedNote {
                Text(noteText)
                    .font(.caption)
                    .foregroundStyle(SemanticColor.onSurfaceVariant)
                    .lineLimit(1)
            }

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
                        Text(expense.createdAt.relativeFormatted)
                            .font(.caption)
                            .foregroundStyle(SemanticColor.onSurfaceVariant)
                    }
                }

                Spacer()

                // Trailing: amount
                Text(expense.amount.displayAmount)
                    .font(.system(.body, design: .monospaced).monospacedDigit())
                    .foregroundStyle(SemanticColor.onSurface)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        var label = "\(partnerInitials) spent \(expense.amount.displayAmount) on \(category?.name ?? "unknown"), \(expense.createdAt.relativeFormatted)"
        if let note = expense.note, !note.isEmpty {
            label += ", note: \(note)"
        }
        return label
    }

    // MARK: - Subviews

    private var categoryBadge: some View {
        let color = CategoryColor(from: category?.colorName ?? "CoolGray")?.color ?? .gray
        return Image(systemName: category?.iconName ?? "ellipsis.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
    }

    private var partnerCircle: some View {
        let color = PartnerColor.color(isCurrentUser: isCurrentUser, colorScheme: colorScheme)
        return Text(partnerInitials)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(color, in: Circle())
    }
}

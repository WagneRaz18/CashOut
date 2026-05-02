import SwiftUI

struct CategoryBreakdownView: View {
    let slices: [InsightsViewModel.ChartSlice]
    let totalAmount: Int64
    let excludedCategories: Set<UUID>
    let onCategoryFilterToggled: (UUID) -> Void

    var body: some View {
        if slices.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: Spacing.sm) {
                ForEach(slices) { slice in
                    let isExcluded = excludedCategories.contains(slice.categoryID)
                    let proportion = isExcluded ? 0.0 : (totalAmount > 0 ? Double(slice.total) / Double(totalAmount) : 0.0)

                    Button {
                        onCategoryFilterToggled(slice.categoryID)
                    } label: {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack(spacing: Spacing.sm) {
                                categoryBadge(iconName: slice.iconName, colorName: slice.colorName)

                                Text(slice.categoryName)
                                    .font(.subheadline)
                                    .foregroundStyle(SemanticColor.onSurface)

                                Spacer()

                                Text(slice.total.displayAmount)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .foregroundStyle(SemanticColor.onSurface)
                            }

                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(CategoryColor(from: slice.colorName)?.color ?? .gray)
                                    .frame(width: max(geometry.size.width * proportion, 2))
                            }
                            .frame(height: 4)
                        }
                        .padding(.vertical, Spacing.xs)
                        .opacity(isExcluded ? 0.35 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(slice.categoryName), \(slice.total.displayAmount), \(Int(proportion * 100))% of total")
                    .accessibilityValue(isExcluded ? "excluded" : "included")
                    .accessibilityHint(isExcluded ? "Double tap to include in chart" : "Double tap to exclude from chart")
                }
            }
            .padding(.horizontal, Spacing.md)
        }
    }

    // MARK: - Subviews

    private func categoryBadge(iconName: String, colorName: String) -> some View {
        let color = CategoryColor(from: colorName)?.color ?? .gray
        return Image(systemName: iconName)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: Circle())
    }
}

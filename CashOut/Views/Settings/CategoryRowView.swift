import SwiftUI

struct CategoryRowView: View {
    let category: CategoryData

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: category.iconName)
                .foregroundStyle(CategoryColor(from: category.colorName)?.color ?? .gray)
                .imageScale(.medium)
            Text(category.name)
            Spacer()
            if category.isDefault {
                Text("Default")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .imageScale(.small)
        }
        .accessibilityElement(children: .combine)
    }
}

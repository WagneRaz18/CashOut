import SwiftUI

struct CategoryPickerView: View {
    let categories: [CategoryData]
    let selectedCategoryID: UUID?
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(categories, id: \.id) { category in
                        categoryChip(category)
                            .id(category.id)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            .task(id: selectedCategoryID) {
                if let selectedCategoryID {
                    withAnimation {
                        proxy.scrollTo(selectedCategoryID, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func categoryChip(_ category: CategoryData) -> some View {
        let isSelected = category.id == selectedCategoryID
        let categoryColor = Color(category.colorName)

        Button {
            onSelect(category.id)
        } label: {
            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 8, height: 8)

                Text(category.name)
                    .font(.subheadline)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 44)
            .background(
                isSelected
                    ? categoryColor.opacity(0.15)
                    : Color.clear
            )
            .foregroundStyle(isSelected ? categoryColor : .secondary)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        isSelected ? categoryColor : Color.clear,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    CategoryPickerView(
        categories: [
            CategoryData(id: UUID(), name: "Food & Drink", iconName: "fork.knife", colorName: "Sage", isDefault: true, sortOrder: 0),
            CategoryData(id: UUID(), name: "Transport", iconName: "car.fill", colorName: "Slate", isDefault: true, sortOrder: 1),
            CategoryData(id: UUID(), name: "Entertainment", iconName: "film.fill", colorName: "Lavender", isDefault: true, sortOrder: 2),
        ],
        selectedCategoryID: nil,
        onSelect: { _ in }
    )
    .frame(height: 60)
}

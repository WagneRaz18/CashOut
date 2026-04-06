import SwiftUI

struct CategoryManagementView: View {
    let category: CategoryData?
    @Bindable var viewModel: SettingsViewModel

    @State private var name: String
    @State private var selectedIcon: String
    @State private var selectedColor: CategoryColor
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss

    private static let availableIcons: [String] = [
        "star.fill", "heart.fill", "gift.fill", "cart.fill", "cup.and.saucer.fill",
        "airplane", "bus.fill", "bicycle", "fuelpump.fill", "cross.case.fill",
        "book.fill", "graduationcap.fill", "music.note", "gamecontroller.fill", "pawprint.fill",
        "wrench.fill", "scissors", "leaf.fill", "drop.fill", "flame.fill",
        "creditcard.fill", "banknote.fill", "phone.fill", "wifi"
    ]

    private static let iconLabels: [String: String] = [
        "star.fill": "Star", "heart.fill": "Heart", "gift.fill": "Gift",
        "cart.fill": "Shopping Cart", "cup.and.saucer.fill": "Coffee",
        "airplane": "Airplane", "bus.fill": "Bus", "bicycle": "Bicycle",
        "fuelpump.fill": "Fuel", "cross.case.fill": "Medical",
        "book.fill": "Book", "graduationcap.fill": "Education",
        "music.note": "Music", "gamecontroller.fill": "Gaming",
        "pawprint.fill": "Pets", "wrench.fill": "Tools",
        "scissors": "Scissors", "leaf.fill": "Nature",
        "drop.fill": "Water", "flame.fill": "Fire",
        "creditcard.fill": "Credit Card", "banknote.fill": "Cash",
        "phone.fill": "Phone", "wifi": "Internet"
    ]

    private static let iconColumns = Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 5)

    init(category: CategoryData?, viewModel: SettingsViewModel) {
        self.category = category
        self.viewModel = viewModel
        _name = State(initialValue: category?.name ?? "")
        _selectedIcon = State(initialValue: category?.iconName ?? "star.fill")
        _selectedColor = State(initialValue: CategoryColor(from: category?.colorName ?? "") ?? .teal)
    }

    var body: some View {
        Form {
            nameSection
            iconSection
            colorSection
            saveSection
        }
        .navigationTitle(category == nil ? "New Category" : "Edit Category")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.categorySaveError = nil }
        .onDisappear { saveTask?.cancel() }
    }

    // MARK: - Sections

    private var nameSection: some View {
        Section("Name") {
            TextField("Category Name", text: $name)
                .onChange(of: name) { _, newValue in
                    if newValue.count > 30 {
                        name = String(newValue.prefix(30))
                    }
                }
            HStack {
                Spacer()
                Text("\(name.count)/30")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconSection: some View {
        Section("Icon") {
            LazyVGrid(columns: Self.iconColumns, spacing: Spacing.sm) {
                ForEach(Self.availableIcons, id: \.self) { iconName in
                    let isSelected = iconName == selectedIcon
                    Button {
                        selectedIcon = iconName
                    } label: {
                        Image(systemName: iconName)
                            .font(.title3)
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundStyle(isSelected ? selectedColor.color : .secondary)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? selectedColor.color.opacity(0.15) : .clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(isSelected ? selectedColor.color : .clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.iconLabels[iconName] ?? iconName)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, Spacing.xs)
        }
    }

    private var colorSection: some View {
        Section("Color") {
            HStack(spacing: Spacing.md) {
                ForEach(CategoryColor.customPalette, id: \.rawValue) { colorOption in
                    let isSelected = colorOption == selectedColor
                    Button {
                        selectedColor = colorOption
                    } label: {
                        Circle()
                            .fill(colorOption.color)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.white)
                                    .opacity(isSelected ? 1 : 0)
                            )
                            .overlay(
                                Circle()
                                    .strokeBorder(isSelected ? colorOption.color : .clear, lineWidth: 3)
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(colorOption.rawValue)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity)
        }
    }

    private var saveSection: some View {
        Section {
            Button("Save") {
                saveTask?.cancel()
                saveTask = Task {
                    await viewModel.saveCategory(
                        name: name,
                        iconName: selectedIcon,
                        colorName: selectedColor.rawValue,
                        existingID: category?.id
                    )
                    guard !Task.isCancelled else { return }
                    if viewModel.categorySaveError == nil {
                        dismiss()
                    }
                }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSavingCategory)
            .frame(maxWidth: .infinity)

            if let error = viewModel.categorySaveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

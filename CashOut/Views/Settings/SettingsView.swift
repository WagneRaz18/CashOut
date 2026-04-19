import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "SettingsView")

struct SettingsView: View {
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        Group {
            if let viewModel {
                SettingsContent(viewModel: viewModel)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Settings")
        .task {
            if viewModel == nil {
                viewModel = SettingsViewModel()
            }
            guard let viewModel else { return }
            await viewModel.loadCategories()
        }
    }
}

// MARK: - Settings Content

private struct SettingsContent: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Bindable var viewModel: SettingsViewModel
    @State private var isShowingAddCategory = false
    @State private var categoryToEdit: CategoryData?
    @State private var isShowingSignOutAlert = false
    @State private var categoryToDelete: CategoryData?
    @State private var deleteTask: Task<Void, Never>?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            Section("Categories") {
                ForEach(viewModel.categories, id: \.id) { category in
                    if category.isDefault {
                        CategoryRowView(category: category)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    categoryToDelete = category
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    } else {
                        Button {
                            categoryToEdit = category
                        } label: {
                            HStack {
                                CategoryRowView(category: category)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Double tap to edit")
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                categoryToDelete = category
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .onMove { from, to in
                    viewModel.moveCategory(from: from, to: to)
                }
                Button {
                    isShowingAddCategory = true
                } label: {
                    Label("Add Category", systemImage: "plus.circle")
                }
            }

            Section("Household") {
                HouseholdPairingView(
                    householdService: HouseholdService.shared,
                    publicSync: PublicSyncService.shared,
                    expenseRepository: ExpenseRepository.shared
                )
            }

            Section("Account") {
                Button(role: .destructive) {
                    isShowingSignOutAlert = true
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.appVersion)
                Text("Your data stays on your devices and iCloud. No analytics, no third-party access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .navigationDestination(isPresented: $isShowingAddCategory) {
            CategoryManagementView(category: nil, viewModel: viewModel)
        }
        .navigationDestination(item: $categoryToEdit) { category in
            CategoryManagementView(category: category, viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(editMode == .active ? "Done" : "Edit") {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
            }
        }
        .onDisappear {
            logger.debug("SettingsContent.onDisappear — cancelling tasks")
            deleteTask?.cancel()
        }
        .alert("Sign Out", isPresented: $isShowingSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                authViewModel.signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will need to sign in again with your Apple ID to sync expenses.")
        }
        .alert(
            "Delete Category?",
            isPresented: Binding(
                get: { categoryToDelete != nil },
                set: { if !$0 { categoryToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                guard let category = categoryToDelete else { return }
                categoryToDelete = nil
                deleteTask?.cancel()
                deleteTask = Task { await viewModel.deleteCategory(id: category.id) }
            }
            Button("Cancel", role: .cancel) {
                categoryToDelete = nil
            }
        } message: {
            if let category = categoryToDelete {
                Text("'\(category.name)' will be removed for you and your partner.")
            }
        }
        .alert(
            "Cannot Delete",
            isPresented: Binding(
                get: { viewModel.categoryDeleteError != nil },
                set: { if !$0 { viewModel.categoryDeleteError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.categoryDeleteError = nil
            }
        } message: {
            if let error = viewModel.categoryDeleteError {
                Text(error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthenticationViewModel())
}

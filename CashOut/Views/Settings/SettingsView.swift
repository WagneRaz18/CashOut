import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @State private var viewModel = SettingsViewModel()
    @State private var isShowingAddCategory = false
    @State private var isShowingSignOutAlert = false
    @State private var categoryToDelete: CategoryData?
    @State private var deleteTask: Task<Void, Never>?
    @State private var cancelInviteTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Categories") {
                ForEach(viewModel.categories, id: \.id) { category in
                    Group {
                        if category.isDefault {
                            CategoryRowView(category: category)
                        } else {
                            NavigationLink(destination: CategoryManagementView(
                                category: category,
                                viewModel: viewModel
                            )) {
                                CategoryRowView(category: category)
                            }
                            .accessibilityHint("Double tap to edit")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            categoryToDelete = category
                        } label: {
                            Label("Delete", systemImage: "trash")
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
                HouseholdSectionView(viewModel: viewModel)
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
        .navigationDestination(isPresented: $isShowingAddCategory) {
            CategoryManagementView(category: nil, viewModel: viewModel)
        }
        .navigationTitle("Settings")
        .onDisappear {
            deleteTask?.cancel()
            cancelInviteTask?.cancel()
        }
        // Both calls re-fire on every NavigationStack appear — intentional.
        // Categories list is small, re-fetch ensures partner-added custom categories
        // appear immediately via NSPersistentCloudKitContainer auto-merge.
        .task {
            await viewModel.refreshSharingStatus()
            await viewModel.loadCategories()
        }
        .alert("Cancel Invitation", isPresented: Bindable(viewModel).isShowingCancelAlert) {
            Button("Cancel Invitation", role: .destructive) {
                cancelInviteTask?.cancel()
                cancelInviteTask = Task { await viewModel.cancelInvitation() }
            }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("This will revoke the invitation link. You can invite a partner again later.")
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
        .sheet(isPresented: Bindable(viewModel).isShowingShareSheet, onDismiss: {
            // Catches interactive dismiss (swipe-down) when no delegate method fires.
            // Safe to call unconditionally — handleShareDismiss is idempotent per presentation.
            viewModel.handleShareDismiss(nil)
        }) {
            if let share = viewModel.activeShare,
               let container = viewModel.activeContainer {
                CloudSharingSheet(share: share, container: container) { updatedShare in
                    viewModel.handleShareDismiss(updatedShare)
                }
            }
        }
    }
}

// MARK: - Household Section

private struct HouseholdSectionView: View {
    @Bindable var viewModel: SettingsViewModel
    @State private var inviteTask: Task<Void, Never>?
    @State private var resendTask: Task<Void, Never>?
    @State private var cancelTask: Task<Void, Never>?

    var body: some View {
        Group {
            if viewModel.hasPartner {
                HStack {
                    partnerAvatar
                    VStack(alignment: .leading) {
                        Text(viewModel.partnerDisplayName ?? "Partner")
                            .font(.body)
                        Text("Connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            } else if viewModel.isPendingInvitation {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text("Invitation Pending")
                            .font(.body)
                        Text("Waiting for partner to accept")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                Button("Resend Invitation") {
                    resendTask?.cancel()
                    resendTask = Task { await viewModel.resendInvitation() }
                }
                .disabled(viewModel.isInviting)

                Button("Cancel Invitation", role: .destructive) {
                    viewModel.isShowingCancelAlert = true
                }
                .disabled(viewModel.isCancelling)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Button("Invite Partner") {
                    inviteTask?.cancel()
                    inviteTask = Task { await viewModel.invitePartner() }
                }
                .disabled(viewModel.isInviting)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .onDisappear {
            inviteTask?.cancel()
            resendTask?.cancel()
            cancelTask?.cancel()
        }
    }

    private var partnerAvatar: some View {
        let initials = viewModel.partnerDisplayName
            .map { name in
                let parts = name.split(separator: " ")
                if parts.count >= 2 {
                    return String(parts[0].prefix(1) + parts[1].prefix(1))
                }
                return String(name.prefix(2))
            } ?? "P"

        return Text(initials.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color(red: 0.659, green: 0.608, blue: 0.541)) // #A89B8A warm stone
            .clipShape(Circle())
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environment(AuthenticationViewModel())
}

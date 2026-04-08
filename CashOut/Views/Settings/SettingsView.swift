import SwiftUI
import CloudKit

struct SettingsView: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @State private var viewModel = SettingsViewModel()
    @State private var isShowingAddCategory = false
    @State private var isShowingSignOutAlert = false

    var body: some View {
        Form {
            Section("Categories") {
                ForEach(viewModel.categories, id: \.id) { category in
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
        // Both calls re-fire on every NavigationStack appear — intentional.
        // Categories list is small, re-fetch ensures partner-added custom categories
        // appear immediately via NSPersistentCloudKitContainer auto-merge.
        .task {
            await viewModel.refreshSharingStatus()
            await viewModel.loadCategories()
        }
        .alert("Sign Out", isPresented: $isShowingSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                authViewModel.signOut()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will need to sign in again with your Apple ID to sync expenses.")
        }
        .sheet(isPresented: Bindable(viewModel).isShowingShareSheet, onDismiss: {
            // Catches interactive dismiss (swipe-down) when no delegate method fires
            if viewModel.isShowingShareSheet {
                viewModel.handleShareDismiss(nil)
            }
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
            } else if viewModel.isPendingInvitation {
                HStack {
                    Image(systemName: "clock")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text("Invitation Pending")
                            .font(.body)
                        Text("Waiting for partner to accept")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .onDisappear { inviteTask?.cancel() }
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

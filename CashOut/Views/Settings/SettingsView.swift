import SwiftUI
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "SettingsView")

struct SettingsView: View {
    // Lazy viewModel — the nil default keeps the @State initializer cheap so SwiftUI's
    // unavoidable re-evaluation of this view inside parent .navigationDestination
    // closures does not allocate a SettingsViewModel. Real construction happens in
    // .task, which only fires when the view is actually on screen.
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
            // Both methods are @MainActor-isolated — they serialize on the
            // main actor regardless of `async let`, so sequential `await` is
            // equivalent at runtime and avoids the Swift 6 "non-Sendable type
            // cannot exit main actor" error (see .claude/learnings/ios-swiftui.md).
            await viewModel.refreshSharingStatus()
            await viewModel.loadCategories()
        }
    }
}

// MARK: - Settings Content (owns all transient tasks)

private struct SettingsContent: View {
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @Bindable var viewModel: SettingsViewModel
    @State private var isShowingAddCategory = false
    @State private var categoryToEdit: CategoryData?
    @State private var isShowingSignOutAlert = false
    @State private var categoryToDelete: CategoryData?
    @State private var deleteTask: Task<Void, Never>?
    @State private var cancelInviteTask: Task<Void, Never>?
    // Invite/resend tasks live here, not inside HouseholdSectionView — the section
    // view sits underneath the share sheet, so its onDisappear would cancel an
    // in-flight invite the moment the sheet presents. Scoping tasks to the full
    // Settings screen ensures they survive sheet presentation.
    @State private var inviteTask: Task<Void, Never>?
    @State private var resendTask: Task<Void, Never>?
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
                        // Button + navigationDestination(item:) — defers
                        // CategoryManagementView allocation until the user taps
                        // the row. NavigationLink(destination:) would eagerly
                        // allocate every destination on every body re-evaluation.
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
                HouseholdSectionView(
                    viewModel: viewModel,
                    onInvite: {
                        inviteTask?.cancel()
                        inviteTask = Task { await viewModel.invitePartner() }
                    },
                    onResend: {
                        resendTask?.cancel()
                        resendTask = Task { await viewModel.resendInvitation() }
                    }
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
            cancelInviteTask?.cancel()
            inviteTask?.cancel()
            resendTask?.cancel()
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
        .sheet(isPresented: Bindable(viewModel).isShowingShareSheet) {
            // The CloudSharingSheet Coordinator owns every dismissal path via
            // UICloudSharingControllerDelegate + UIAdaptivePresentationControllerDelegate.
            // SwiftUI's `.onDismiss:` would race the Coordinator callbacks, so we omit it
            // here — the Coordinator's `fireDismissOnce` is the single source of truth.
            if let share = viewModel.activeShare,
               let container = viewModel.activeContainer {
                CloudSharingSheet(share: share, container: container) { updatedShare, error in
                    viewModel.handleShareDismiss(updatedShare, error: error)
                }
            }
        }
    }
}

// MARK: - Household Section

private struct HouseholdSectionView: View {
    @Bindable var viewModel: SettingsViewModel
    let onInvite: () -> Void
    let onResend: () -> Void

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

                Button("Resend Invitation", action: onResend)
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
                Button("Invite Partner", action: onInvite)
                    .disabled(viewModel.isInviting)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
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

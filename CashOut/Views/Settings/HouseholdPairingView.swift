import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "HouseholdPairingView")

/// Three-branch Household pairing UI.
///
/// - Unpaired: prompt for display name, then offer Create code / Enter code.
/// - Paired: show current code, display-name editor, and Unpair button.
///
/// Replaces the prior CKShare-based `HouseholdSectionView`. No URL routing, no Messages
/// dependency, no scene delegate. The household code is shared over any channel the users
/// prefer (text, verbal, etc.) — acceptance is "type this 8-char code on your phone."
///
/// Services are injected as `let` from the parent (`SettingsContent`) — not `@State` —
/// to avoid double-initialising `NWPathMonitor` on view-state resets.
struct HouseholdPairingView: View {
    let householdService: HouseholdService
    let publicSync: PublicSyncService
    let expenseRepository: ExpenseRepositoryProtocol

    @State private var entryCode: String = ""
    @State private var entryError: String?
    @State private var isPairing = false
    @State private var isShowingUnpairAlert = false
    @State private var pairTask: Task<Void, Never>?
    @State private var createTask: Task<Void, Never>?
    @State private var unpairTask: Task<Void, Never>?
    @FocusState private var entryFocused: Bool

    var body: some View {
        Group {
            if householdService.isPaired {
                pairedView
            } else {
                unpairedView
            }
        }
        .onDisappear {
            logger.debug("HouseholdPairingView.onDisappear — cancelling tasks")
            pairTask?.cancel()
            createTask?.cancel()
            unpairTask?.cancel()
        }
    }

    // MARK: - Paired

    @ViewBuilder
    private var pairedView: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading) {
                Text("Paired")
                    .font(.body)
                if let code = householdService.householdCode {
                    Text("Code: \(HouseholdService.formatted(code))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }

        LabeledContent("Your display name") {
            TextField("Your name", text: Bindable(householdService).displayName)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }

        Button(role: .destructive) {
            isShowingUnpairAlert = true
        } label: {
            Label("Unpair (stop syncing)", systemImage: "link.badge.minus")
        }
        .alert("Unpair from household?", isPresented: $isShowingUnpairAlert) {
            Button("Unpair", role: .destructive) { unpair() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stop syncing with your partner's device. Your existing expenses stay on this phone. You can pair again any time.")
        }
    }

    // MARK: - Unpaired

    @ViewBuilder
    private var unpairedView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync expenses with your partner")
                .font(.subheadline.weight(.semibold))
            Text("Pair by sharing a short code. No Apple ID invite required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Your display name") {
            TextField("Your name", text: Bindable(householdService).displayName)
                .multilineTextAlignment(.trailing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
        }

        Button {
            createCode()
        } label: {
            Label("Create household code", systemImage: "plus.circle")
        }
        .disabled(isPairing || displayNameIsEmpty)

        VStack(alignment: .leading, spacing: 8) {
            Text("Or enter your partner's code")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("ABCD-EFGH", text: $entryCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
                .focused($entryFocused)
                .onChange(of: entryCode) { _, newValue in
                    let cleaned = newValue
                        .uppercased()
                        .filter { $0.isLetter || $0.isNumber }
                        .prefix(8)
                    if cleaned != Substring(newValue) {
                        entryCode = String(cleaned)
                    }
                }
            Button {
                pair()
            } label: {
                if isPairing {
                    ProgressView()
                } else {
                    Label("Pair with code", systemImage: "link.badge.plus")
                }
            }
            .disabled(entryCode.count != 8 || isPairing || displayNameIsEmpty)
            if let entryError {
                Text(entryError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if displayNameIsEmpty {
                Text("Enter your display name above before pairing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayNameIsEmpty: Bool {
        householdService.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func createCode() {
        logger.info("createCode: generating")
        let code = householdService.generateCode()
        createTask?.cancel()
        createTask = Task {
            await publicSync.registerSubscriptions()
            // Backfill any pre-existing local records so they sync to the partner on
            // first fetch without requiring each row to be edited individually.
            await publicSync.backfillAllLocalRecords()
            expenseRepository.reloadObservation()
            logger.info("createCode: subscriptions registered + backfill submitted (code \(code, privacy: .private))")
        }
    }

    private func pair() {
        isPairing = true
        entryError = nil
        let success = householdService.pair(code: entryCode)
        guard success else {
            entryError = "That code doesn't look right. It's 8 characters — letters and numbers only."
            isPairing = false
            return
        }
        logger.info("pair: code stored — registering subscriptions + fetching changes")
        pairTask?.cancel()
        pairTask = Task {
            await publicSync.registerSubscriptions()
            await publicSync.backfillAllLocalRecords()
            await publicSync.fetchChanges()
            expenseRepository.reloadObservation()
            if Task.isCancelled { return }
            isPairing = false
            entryCode = ""
            entryFocused = false
        }
    }

    private func unpair() {
        logger.info("unpair: removing subscriptions + clearing code")
        unpairTask?.cancel()
        unpairTask = Task {
            await publicSync.removeSubscriptions()
            if Task.isCancelled { return }
            householdService.unpair()
            publicSync.resetFetchCursor()
            expenseRepository.reloadObservation()
        }
    }
}

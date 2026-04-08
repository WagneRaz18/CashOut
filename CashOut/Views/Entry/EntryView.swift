import SwiftUI

// MARK: - Save Success Animation Phases

private enum SaveSuccessPhase: CaseIterable {
    case hidden, pop, hold, fadeOut
}

struct EntryView: View {
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var viewModel = ExpenseEntryViewModel()
    @State private var showingNoteSheet = false
    @State private var saveTask: Task<Void, Never>?
    @State private var animationTask: Task<Void, Never>?
    @State private var showSuccessOverlay = false
    @State private var showCheckmark = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SemanticColor.error)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            AmountDisplayView(amount: viewModel.amountInSatang)
                .padding(.horizontal, Spacing.md)

            Button {
                showingNoteSheet = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: viewModel.noteText.isEmpty ? "square.and.pencil" : "note.text")
                        .font(.subheadline)
                    Text(viewModel.noteText.isEmpty ? "Add note" : viewModel.noteText)
                        .font(.subheadline)
                        .lineLimit(1)
                }
                .foregroundStyle(SemanticColor.onSurfaceVariant)
            }
            .buttonStyle(.plain)
            .padding(.bottom, Spacing.sm)
            .accessibilityLabel(viewModel.noteText.isEmpty ? "Add note" : "Edit note")

            Spacer(minLength: 0)

            if viewModel.categoryLoadFailed {
                Button {
                    Task { await viewModel.retryLoadCategories() }
                } label: {
                    Label("Categories unavailable — tap to retry", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(SemanticColor.error)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry loading categories")
                .accessibilityHint("Loads the category list again")
                .padding(.vertical, Spacing.sm)
            } else {
                CategoryPickerView(
                    categories: viewModel.categories,
                    selectedCategoryID: viewModel.selectedCategoryID,
                    onSelect: { viewModel.selectCategory($0) }
                )
                .padding(.vertical, Spacing.sm)
            }

            NumpadView(
                onDigit: { viewModel.appendDigit($0) },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            SaveButtonView(
                isDisabled: viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil,
                saveCount: viewModel.saveCount,
                showCheckmark: showCheckmark,
                onSave: {
                    saveTask?.cancel()
                    saveTask = Task {
                        do {
                            viewModel.saveError = nil
                            try await viewModel.saveExpense()
                            guard !Task.isCancelled else { return }
                            // Animation sequence is driven by .onChange(of: viewModel.saveCount)
                        } catch {
                            guard !Task.isCancelled else { return }
                            viewModel.saveError = "Could not save entry. Please try again."
                        }
                    }
                }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .background(Surface.base.ignoresSafeArea())
        .overlay { successOverlay }
        .task {
            await viewModel.loadCategories()
        }
        .sheet(isPresented: $showingNoteSheet) {
            NoteEntrySheet(noteText: $viewModel.noteText)
                .presentationDetents([.large])
        }
        .onChange(of: viewModel.saveCount) {
            handleSaveSuccess()
        }
        .onDisappear {
            saveTask?.cancel()
            animationTask?.cancel()
        }
    }

    // MARK: - Success Overlay

    @ViewBuilder
    private var successOverlay: some View {
        if reduceMotion {
            // Accessibility: simple opacity, no scale/spring
            if showSuccessOverlay {
                successCheckmark
                    .transition(.opacity)
            }
        } else {
            // PhaseAnimator stays permanently in the tree — .hidden phase is invisible.
            // Conditional removal would cause re-insertion auto-cycle on 2nd+ saves.
            PhaseAnimator(SaveSuccessPhase.allCases, trigger: viewModel.saveCount) { phase in
                successCheckmark
                    .scaleEffect(scaleForPhase(phase))
                    .opacity(opacityForPhase(phase))
            } animation: { phase in
                animationForPhase(phase)
            }
        }
    }

    private var successCheckmark: some View {
        Circle()
            .fill(SemanticColor.success.opacity(0.2))
            .frame(width: 88, height: 88)
            .overlay {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(SemanticColor.success)
            }
    }

    // MARK: - Phase Animation Helpers

    private func scaleForPhase(_ phase: SaveSuccessPhase) -> CGFloat {
        switch phase {
        case .hidden: 0.01
        case .pop: 1.3
        case .hold: 1.0
        case .fadeOut: 0.9
        }
    }

    private func opacityForPhase(_ phase: SaveSuccessPhase) -> Double {
        switch phase {
        case .hidden: 0
        case .pop: 1
        case .hold: 1
        case .fadeOut: 0
        }
    }

    private func animationForPhase(_ phase: SaveSuccessPhase) -> Animation {
        switch phase {
        case .hidden: .easeOut(duration: 0.1)
        case .pop: .spring(response: 0.3, dampingFraction: 0.5)
        case .hold: .easeOut(duration: 0.15)
        case .fadeOut: .easeIn(duration: 0.25)
        }
    }

    // MARK: - Save Success Sequence

    private func handleSaveSuccess() {
        withAnimation { showCheckmark = true }
        withAnimation { showSuccessOverlay = true }
        UIAccessibility.post(notification: .announcement, argument: "Expense saved")

        animationTask?.cancel()
        animationTask = Task { @MainActor in
            let resetDelay: UInt64 = reduceMotion ? 600_000_000 : 1_000_000_000
            do {
                try await Task.sleep(nanoseconds: resetDelay)
            } catch { return }
            guard !Task.isCancelled else { return }

            viewModel.resetForm()
            withAnimation { showSuccessOverlay = false }
            withAnimation { showCheckmark = false }

            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch { return }
            guard !Task.isCancelled else { return }

            onSaveComplete?()
        }
    }
}

#Preview {
    EntryView()
}

#Preview("Dynamic Type — AX3") {
    EntryView()
        .dynamicTypeSize(.accessibility3)
}

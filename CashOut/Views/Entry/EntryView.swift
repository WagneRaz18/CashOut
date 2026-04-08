import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "EntryView")

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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(SemanticColor.error)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            Spacer(minLength: 0)

            AmountDisplayView(amount: viewModel.amountInSatang)
                .padding(.horizontal, Spacing.lg)

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
                    logger.info("Category retry tapped")
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
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.xl)
            }

            NumpadView(
                onDigit: { viewModel.appendDigit($0) },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            SaveButtonView(
                isDisabled: viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil,
                saveCount: viewModel.saveCount,
                showCheckmark: showCheckmark,
                onSave: {
                    logger.info("Save button tapped — amount=\(viewModel.amountInBaht, privacy: .private) Baht")
                    saveTask?.cancel()
                    saveTask = Task {
                        do {
                            viewModel.saveError = nil
                            try await viewModel.saveExpense()
                            guard !Task.isCancelled else { return }
                            // Animation sequence is driven by .onChange(of: viewModel.saveCount)
                        } catch {
                            guard !Task.isCancelled else { return }
                            logger.error("Save failed in EntryView — showing user error")
                            viewModel.saveError = "Could not save entry. Please try again."
                        }
                    }
                }
            )
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.md)
        }
        .background {
            Surface.base.ignoresSafeArea()

            if !reduceTransparency {
                // Ambient atmospheric glow — matches mockup
                Circle()
                    .fill(SemanticColor.primary.opacity(0.10))
                    .blur(radius: 120)
                    .frame(width: 400, height: 280)
                    .offset(x: 120, y: -80)
                    .allowsHitTesting(false)

                Circle()
                    .fill(SemanticColor.tertiary.opacity(0.05))
                    .blur(radius: 100)
                    .frame(width: 340, height: 210)
                    .offset(x: -100, y: 300)
                    .allowsHitTesting(false)
            }
        }
        .drawingGroup()
        .overlay { successOverlay }
        .task {
            logger.debug("EntryView.task: loading categories")
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
            logger.debug("EntryView.onDisappear — cancelling tasks")
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
        logger.info("Save success — starting animation sequence (saveCount=\(viewModel.saveCount))")
        withAnimation { showCheckmark = true; showSuccessOverlay = true }
        UIAccessibility.post(notification: .announcement, argument: "Expense saved")

        animationTask?.cancel()
        animationTask = Task { @MainActor in
            let resetDelay: UInt64 = reduceMotion ? 400_000_000 : 700_000_000
            do {
                try await Task.sleep(nanoseconds: resetDelay)
            } catch { return }

            logger.debug("Animation complete — resetting form")
            viewModel.resetForm()
            withAnimation { showSuccessOverlay = false; showCheckmark = false }

            do {
                try await Task.sleep(nanoseconds: 100_000_000)
            } catch { return }

            logger.debug("Post-save: switching to Feed tab")
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

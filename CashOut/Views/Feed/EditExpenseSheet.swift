import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "EditExpenseSheet")

struct EditExpenseSheet: View {
    let expense: ExpenseData
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var viewModel: EditExpenseViewModel
    @State private var showingNoteSheet = false
    @State private var saveTask: Task<Void, Never>?
    @State private var saveTrigger: Int = 0

    init(
        expense: ExpenseData,
        onSaveComplete: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.expense = expense
        self.onSaveComplete = onSaveComplete
        _viewModel = State(initialValue: EditExpenseViewModel(expense: expense))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = viewModel.saveError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            AmountDisplayView(amount: viewModel.amountInSatang)
                .overlay { SaveConfirmationOverlay(trigger: saveTrigger) }
                .padding(.top, Spacing.lg)
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

            CategoryPickerView(
                categories: viewModel.categories,
                selectedCategoryID: viewModel.selectedCategoryID,
                onSelect: { viewModel.selectCategory($0) }
            )
            .padding(.vertical, Spacing.sm)

            NumpadView(
                onDigit: { viewModel.appendDigit($0) },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            SaveButtonView(
                isDisabled: viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil,
                onSave: {
                    logger.info("Edit save tapped — amount=\(viewModel.amountInBaht, privacy: .private) Baht")

                    // Immediate: animation + haptic (optimistic, same frame as tap)
                    saveTrigger += 1
                    HapticService.shared.trigger(.saveTap)

                    saveTask?.cancel()
                    saveTask = Task {
                        // Save runs in parallel with animation
                        async let save: Void = viewModel.saveExpense()

                        // Wait for animation to complete
                        do {
                            try await Task.sleep(for: .milliseconds(400))
                        } catch is CancellationError { return }
                        guard !Task.isCancelled else { return }

                        // Collect save result
                        do {
                            try await save
                        } catch {
                            guard !Task.isCancelled else { return }
                            logger.error("Edit save failed: \(error.localizedDescription, privacy: .public)")
                            viewModel.saveError = "Could not save changes. Please try again."
                            return
                        }

                        // Save succeeded — cleanup must always run
                        logger.info("Edit save succeeded — dismissing sheet")
                        UIAccessibility.post(notification: .announcement, argument: "Changes saved")
                        onSaveComplete?()
                    }
                }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
        .task {
            logger.debug("EditExpenseSheet.task: loading categories for edit")
            await viewModel.loadCategories()
        }
        .sheet(isPresented: $showingNoteSheet) {
            NoteEntrySheet(noteText: $viewModel.noteText)
                .presentationDetents([.large])
        }
        .onDisappear {
            saveTask?.cancel()
        }
    }
}

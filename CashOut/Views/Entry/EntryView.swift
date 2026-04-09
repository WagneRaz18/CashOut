import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "EntryView")

struct EntryView: View {
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var viewModel = ExpenseEntryViewModel()
    @State private var showingNoteSheet = false
    @State private var saveTask: Task<Void, Never>?
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
                onSave: {
                    logger.info("Save button tapped — amount=\(viewModel.amountInBaht, privacy: .private) Baht")
                    let tapStart = CFAbsoluteTimeGetCurrent()
                    saveTask?.cancel()
                    saveTask = Task {
                        do {
                            viewModel.saveError = nil
                            try await viewModel.saveExpense()
                            guard !Task.isCancelled else { return }
                            let tapElapsed = (CFAbsoluteTimeGetCurrent() - tapStart) * 1000
                            logger.info("Save success — navigating immediately — \(tapElapsed, format: .fixed(precision: 1))ms since tap")
                            UIAccessibility.post(notification: .announcement, argument: "Expense saved")
                            viewModel.resetForm()
                            onSaveComplete?()
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
                ZStack {
                    Circle()
                        .fill(SemanticColor.primary.opacity(0.10))
                        .blur(radius: 120)
                        .frame(width: 400, height: 280)
                        .offset(x: 120, y: -80)

                    Circle()
                        .fill(SemanticColor.tertiary.opacity(0.05))
                        .blur(radius: 100)
                        .frame(width: 340, height: 210)
                        .offset(x: -100, y: 300)
                }
                .drawingGroup()
                .allowsHitTesting(false)
            }
        }
        .task {
            logger.debug("EntryView.task: loading categories")
            await viewModel.loadCategories()
        }
        .sheet(isPresented: $showingNoteSheet) {
            NoteEntrySheet(noteText: $viewModel.noteText)
                .presentationDetents([.large])
        }
        .onDisappear {
            logger.debug("EntryView.onDisappear — cancelling tasks")
            saveTask?.cancel()
            viewModel.cancelPendingShare()
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

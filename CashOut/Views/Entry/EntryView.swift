import SwiftUI

struct EntryView: View {
    var onSaveComplete: (@MainActor @Sendable () -> Void)? = nil

    @State private var viewModel = ExpenseEntryViewModel()
    @State private var showingNoteSheet = false

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
                onSave: {
                    Task {
                        do {
                            viewModel.saveError = nil
                            try await viewModel.saveExpense()
                            guard !Task.isCancelled else { return }
                            onSaveComplete?()
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
        .task {
            await viewModel.loadCategories()
        }
        .sheet(isPresented: $showingNoteSheet) {
            NoteEntrySheet(noteText: $viewModel.noteText)
                .presentationDetents([.large])
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

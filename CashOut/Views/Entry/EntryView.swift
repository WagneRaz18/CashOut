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
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.xs)
            }

            AmountDisplayView(amount: viewModel.amountInCents)
                .padding(.top, Spacing.lg)
                .padding(.horizontal, Spacing.md)

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
                },
                onNoteTap: { showingNoteSheet = true }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
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

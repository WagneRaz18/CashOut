import SwiftUI

struct EntryView: View {
    @State private var viewModel = ExpenseEntryViewModel()
    @State private var showingNoteSheet = false

    var body: some View {
        VStack(spacing: 0) {
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
                onDecimal: { viewModel.appendDecimalPoint() },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.sm)

            SaveButtonView(
                isDisabled: viewModel.isAmountZero || viewModel.isSaving || viewModel.selectedCategoryID == nil,
                onSave: {
                    Task {
                        do {
                            try await viewModel.saveExpense()
                        } catch {
                            #if DEBUG
                            print("Save failed: \(error)")
                            #endif
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

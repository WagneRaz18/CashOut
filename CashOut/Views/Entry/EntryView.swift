import SwiftUI

struct EntryView: View {
    @State private var viewModel = ExpenseEntryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            AmountDisplayView(amount: viewModel.amountInCents)
                .padding(.top, Spacing.lg)
                .padding(.horizontal, Spacing.md)

            Spacer() // Reserved for CategoryPickerView (Story 1.6)

            NumpadView(
                onDigit: { viewModel.appendDigit($0) },
                onDecimal: { viewModel.appendDecimalPoint() },
                onBackspace: { viewModel.deleteLastDigit() }
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }
}

#Preview {
    EntryView()
}

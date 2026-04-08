import SwiftUI

struct SaveButtonView: View {
    let isDisabled: Bool
    let saveCount: Int
    let showCheckmark: Bool
    let onSave: () -> Void

    var body: some View {
        Button {
            onSave()
        } label: {
            Label("Save Transaction", systemImage: showCheckmark ? "checkmark" : "square.and.arrow.down")
                .contentTransition(.symbolEffect(.replace.downUp))
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .symbolEffect(.bounce, value: saveCount)
        .buttonStyle(.glassProminent)
        .disabled(isDisabled || showCheckmark)
        .accessibilityLabel("Save expense")
    }
}

#Preview {
    VStack(spacing: 20) {
        SaveButtonView(isDisabled: false, saveCount: 0, showCheckmark: false, onSave: {})
        SaveButtonView(isDisabled: true, saveCount: 0, showCheckmark: false, onSave: {})
        SaveButtonView(isDisabled: false, saveCount: 1, showCheckmark: true, onSave: {})
    }
    .padding()
}

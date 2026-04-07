import SwiftUI

struct SaveButtonView: View {
    let isDisabled: Bool
    let onSave: () -> Void

    var body: some View {
        Button {
            onSave()
        } label: {
            Label("Save Transaction", systemImage: "square.and.arrow.down")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .disabled(isDisabled)
        .accessibilityLabel("Save expense")
    }
}

#Preview {
    VStack(spacing: 20) {
        SaveButtonView(isDisabled: false, onSave: {})
        SaveButtonView(isDisabled: true, onSave: {})
    }
    .padding()
}

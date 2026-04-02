import SwiftUI

struct SaveButtonView: View {
    let isDisabled: Bool
    let onSave: () -> Void
    let onNoteTap: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                onNoteTap()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Add note")

            Button {
                onSave()
            } label: {
                Text("Save")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .disabled(isDisabled)
            .accessibilityLabel("Save expense")
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SaveButtonView(isDisabled: false, onSave: {}, onNoteTap: {})
        SaveButtonView(isDisabled: true, onSave: {}, onNoteTap: {})
    }
    .padding()
}

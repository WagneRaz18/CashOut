import SwiftUI

struct FloatingAddButton: View {
    var action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Add expense")
    }
}

#Preview {
    FloatingAddButton { }
}

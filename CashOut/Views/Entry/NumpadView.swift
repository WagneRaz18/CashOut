import SwiftUI

struct NumpadView: View {
    let onDigit: (String) -> Void
    let onBackspace: () -> Void

    private let rows: [[NumpadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.empty, .digit("0"), .backspace],
    ]

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: Spacing.sm) {
                    ForEach(rows[rowIndex]) { key in
                        if case .empty = key {
                            Color.clear
                                .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                                .accessibilityHidden(true)
                        } else {
                            Button {
                                handleTap(key)
                            } label: {
                                keyLabel(key)
                                    .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                            }
                            .buttonStyle(.glass)
                            .accessibilityLabel(accessibilityLabel(for: key))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func keyLabel(_ key: NumpadKey) -> some View {
        switch key {
        case .digit(let value):
            Text(value)
                .font(.system(size: 24, weight: .regular, design: .rounded))
                .foregroundStyle(SemanticColor.onSurface)
                .minimumScaleFactor(0.8)
        case .empty:
            Color.clear
        case .backspace:
            Image(systemName: "delete.backward")
                .font(.system(size: 20))
                .foregroundStyle(SemanticColor.onSurfaceVariant)
        }
    }

    private func accessibilityLabel(for key: NumpadKey) -> Text {
        switch key {
        case .digit(let value): Text(value)
        case .empty: Text("")
        case .backspace: Text("Delete")
        }
    }

    private func handleTap(_ key: NumpadKey) {
        switch key {
        case .digit(let value):
            onDigit(value)
        case .empty:
            break
        case .backspace:
            onBackspace()
        }
    }
}

// MARK: - NumpadKey

private enum NumpadKey: Identifiable {
    case digit(String)
    case empty
    case backspace

    var id: String {
        switch self {
        case .digit(let value): "digit-\(value)"
        case .empty: "empty"
        case .backspace: "backspace"
        }
    }
}

#Preview {
    NumpadView(
        onDigit: { _ in },
        onBackspace: {}
    )
    .padding()
}

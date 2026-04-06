import SwiftUI

struct NumpadView: View {
    let onDigit: (String) -> Void
    let onDecimal: () -> Void
    let onBackspace: () -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: Spacing.sm),
        count: 3
    )

    private let rows: [[NumpadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.decimal, .digit("0"), .backspace],
    ]

    var body: some View {
        GeometryReader { geo in
            let keyHeight = max(0, (geo.size.height - Spacing.sm * 3) / 4)

            VStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(rows.flatMap { $0 }) { key in
                        Button {
                            handleTap(key)
                        } label: {
                            keyLabel(key)
                                .frame(maxWidth: .infinity)
                                .frame(height: keyHeight)
                        }
                        .buttonStyle(.glass)
                        .accessibilityLabel(accessibilityLabel(for: key))
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
                .font(.title)
                .minimumScaleFactor(0.8)
        case .decimal:
            Text(".")
                .font(.title)
                .minimumScaleFactor(0.8)
        case .backspace:
            Image(systemName: "delete.backward")
                .font(.title2)
        }
    }

    private func accessibilityLabel(for key: NumpadKey) -> Text {
        switch key {
        case .digit(let value): Text(value)
        case .decimal: Text("Decimal point")
        case .backspace: Text("Delete")
        }
    }

    private func handleTap(_ key: NumpadKey) {
        switch key {
        case .digit(let value):
            onDigit(value)
        case .decimal:
            onDecimal()
        case .backspace:
            onBackspace()
        }
    }
}

// MARK: - NumpadKey

private enum NumpadKey: Identifiable {
    case digit(String)
    case decimal
    case backspace

    var id: String {
        switch self {
        case .digit(let value): "digit-\(value)"
        case .decimal: "decimal"
        case .backspace: "backspace"
        }
    }
}

#Preview {
    NumpadView(
        onDigit: { _ in },
        onDecimal: {},
        onBackspace: {}
    )
    .frame(height: 300)
    .padding()
}

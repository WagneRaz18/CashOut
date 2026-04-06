import SwiftUI

struct AmountDisplayView: View {
    let amount: Int64

    var body: some View {
        Text(amount.displayAmount)
            .font(.system(size: 56, weight: .medium, design: .rounded))
            .foregroundStyle(amount == 0 ? SemanticColor.onSurfaceVariant : SemanticColor.onSurface)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .accessibilityLabel("Amount: \(amount.displayAmount)")
            .accessibilityAddTraits(.updatesFrequently)
    }
}

#Preview {
    VStack(spacing: 20) {
        AmountDisplayView(amount: 0)
        AmountDisplayView(amount: 1250)
    }
}

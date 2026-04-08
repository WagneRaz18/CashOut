import SwiftUI

struct AmountDisplayView: View {
    let amount: Int64

    @ScaledMetric(relativeTo: .largeTitle) private var amountFontSize: CGFloat = 64

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Text("AMOUNT")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(SemanticColor.onSurfaceVariant)
                .tracking(1.2)

            Text(amount.displayAmount)
                .font(.system(size: amountFontSize, weight: .heavy, design: .rounded))
                .tracking(-2)
                .foregroundStyle(amount == 0 ? SemanticColor.secondary : SemanticColor.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
        }
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

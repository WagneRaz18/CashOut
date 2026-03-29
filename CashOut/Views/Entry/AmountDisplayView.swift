import SwiftUI

struct AmountDisplayView: View {
    let amount: Int64

    var body: some View {
        Text(amount.displayAmount)
            .font(.system(size: 48, weight: .medium, design: .rounded))
            .foregroundStyle(amount == 0 ? .secondary : .primary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 20) {
        AmountDisplayView(amount: 0)
        AmountDisplayView(amount: 1250)
    }
}

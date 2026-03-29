import SwiftUI

struct InsightsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text(Int64(0).displayAmount)
                .font(.title)
                .monospacedDigit()

            Text("No entries this period")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Insights")
    }
}

#Preview {
    NavigationStack {
        InsightsView()
    }
}

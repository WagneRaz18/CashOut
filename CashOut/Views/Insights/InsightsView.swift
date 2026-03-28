import SwiftUI

struct InsightsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("$0.00")
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

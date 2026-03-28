import SwiftUI

struct FeedView: View {
    var body: some View {
        Text("No entries yet")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Feed")
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

import SwiftUI

struct FeedView: View {
    @State private var viewModel = FeedViewModel()

    var body: some View {
        Group {
            if viewModel.isEmpty {
                Text("No entries yet")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.expenses, id: \.id) { expense in
                        FeedRowView(
                            expense: expense,
                            category: viewModel.categoryFor(expense),
                            isCurrentUser: viewModel.isCurrentUser(expense),
                            partnerInitials: viewModel.partnerInitials(for: expense)
                        )
                    }
                }
            }
        }
        .navigationTitle("Feed")
        .onAppear {
            viewModel.startObserving()
        }
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
}

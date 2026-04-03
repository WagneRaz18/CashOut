import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @State private var showingAddExpenseSheet = false

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView()
            }
            Tab("Feed", systemImage: "list.bullet", value: 1) {
                NavigationStack {
                    FeedView()
                }
            }
            Tab("Insights", systemImage: "chart.pie", value: 2) {
                NavigationStack {
                    InsightsView()
                }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            if selectedTab != 0 {
                FloatingAddButton {
                    showingAddExpenseSheet = true
                }
            }
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            EntryView(onSaveComplete: {
                showingAddExpenseSheet = false
            })
            .presentationDetents([.large])
        }
    }
}

#Preview {
    ContentView()
        .environment(
            \.managedObjectContext,
            PersistenceController.preview.container.viewContext
        )
}

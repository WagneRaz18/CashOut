import SwiftUI
import CoreData

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
            FloatingAddButton {
                showingAddExpenseSheet = true
            }
            .opacity(selectedTab != 0 ? 1 : 0)
            .allowsHitTesting(selectedTab != 0)
            .accessibilityHidden(selectedTab == 0)
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            EntryView(onSaveComplete: {
                showingAddExpenseSheet = false
            })
            .presentationDetents([.large])
        }
        .task {
            await CloudSharingService.shared.checkSharingStatus()
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard !CloudSharingService.shared.isShared else { continue }
                await CloudSharingService.shared.checkSharingStatus()
            }
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

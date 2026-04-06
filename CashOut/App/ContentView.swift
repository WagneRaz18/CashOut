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
        .task {
            SyncMonitorService.shared.startMonitoring()
            await CloudSharingService.shared.checkSharingStatus()
        }
        .task {
            // Re-check sharing status on remote changes to detect new shares AND revocations
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard !Task.isCancelled else { break }
                await CloudSharingService.shared.checkSharingStatus()
            }
        }
        .task {
            // React to iCloud account changes (sign-out, switch)
            for await _ in NotificationCenter.default.notifications(named: PersistenceController.accountDidChange) {
                guard !Task.isCancelled else { break }
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

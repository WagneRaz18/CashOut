import SwiftUI
import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "ContentView")

struct ContentView: View {
    @State private var selectedTab = 0

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
        .onChange(of: selectedTab) { oldTab, newTab in
            logger.info("Tab switched: \(oldTab) → \(newTab)")
        }
        .task {
            logger.info("ContentView.task: starting sync monitor + sharing check")
            SyncMonitorService.shared.startMonitoring()
            logger.debug("ContentView.task: sync monitor started, awaiting checkSharingStatus")
            await CloudSharingService.shared.checkSharingStatus()
            logger.debug("ContentView.task: checkSharingStatus completed")
        }
        .task {
            logger.debug("ContentView.task: listening for remote store changes")
            // Re-check sharing status on remote changes to detect new shares AND revocations
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard !Task.isCancelled else { break }
                logger.info("Remote store change received — re-checking sharing status")
                await CloudSharingService.shared.checkSharingStatus()
            }
        }
        .task {
            logger.debug("ContentView.task: listening for iCloud account changes")
            // React to iCloud account changes (sign-out, switch)
            for await _ in NotificationCenter.default.notifications(named: PersistenceController.accountDidChange) {
                guard !Task.isCancelled else { break }
                logger.info("iCloud account changed — re-checking sharing status")
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

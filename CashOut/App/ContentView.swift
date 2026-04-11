import SwiftUI
import CoreData
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "ContentView")

/// Zero-size bridge that captures a UIView reference for HapticService configuration.
private struct HapticViewBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isHidden = true
        HapticService.shared.configure(view: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView(onSaveComplete: {
                    withAnimation { selectedTab = 1 }
                })
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
        .background { HapticViewBridge() }
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
            // Debounce: coalesce rapid notifications into a single sharing check.
            // CloudKit sync fires multiple NSPersistentStoreRemoteChange per operation.
            var debounceTask: Task<Void, Never>?
            defer { debounceTask?.cancel() }
            for await _ in NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange) {
                guard !Task.isCancelled else { break }
                let wasCoalesced = debounceTask != nil
                debounceTask?.cancel()
                if wasCoalesced {
                    logger.debug("Remote change notification coalesced (prior debounce cancelled)")
                }
                debounceTask = Task { @MainActor in
                    do {
                        try await Task.sleep(nanoseconds: 500_000_000)
                    } catch is CancellationError { return } catch { return }
                    guard !Task.isCancelled else { return }
                    // Solo-mode short-circuit: NSPersistentStoreRemoteChange in solo
                    // mode is always a local data-change event (FRC, save). Every
                    // path that transitions out of .solo bypasses this guard:
                    // (1) iCloud account change → accountDidChange listener below
                    // (2) createShare() success → state set directly by the service
                    // (3) accepting a share via universal link → AppDelegate calls
                    //     checkSharingStatus() directly, not through this listener
                    // (4) post-acceptance shared-store import → state is already
                    //     != .solo from (3) before this listener observes the import
                    guard CloudSharingService.shared.state != .solo else {
                        logger.debug("Remote store change in solo mode — skipping checkSharingStatus")
                        return
                    }
                    logger.info("Remote store change (debounced) — re-checking sharing status")
                    await CloudSharingService.shared.checkSharingStatus()
                }
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

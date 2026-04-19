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
    @Environment(AuthenticationViewModel.self) private var authViewModel
    @State private var selectedTab = 0
    @State private var entryViewModel = ExpenseEntryViewModel()
    @State private var feedViewModel = FeedViewModel()
    @State private var insightsViewModel = InsightsViewModel()

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Add", systemImage: "plus", value: 0) {
                EntryView(viewModel: entryViewModel, onSaveComplete: {
                    withAnimation { selectedTab = 1 }
                })
            }
            Tab("Feed", systemImage: "list.bullet", value: 1) {
                NavigationStack {
                    FeedView(viewModel: feedViewModel)
                }
            }
            Tab("Insights", systemImage: "chart.pie", value: 2) {
                NavigationStack {
                    InsightsView(viewModel: insightsViewModel)
                }
            }
        }
        .background { HapticViewBridge() }
        .tabBarMinimizeBehavior(.onScrollDown)
        .onChange(of: selectedTab) { oldTab, newTab in
            logger.info("Tab switched: \(oldTab) → \(newTab)")
        }
        .task {
            // All sync/monitor bootstrap now lives in AuthenticationViewModel so the
            // View does not import service singletons directly. Guard in the VM
            // absorbs TabView's re-firing `.task` semantics.
            await authViewModel.bootstrapSyncIfPaired()
        }
        .task {
            logger.debug("ContentView.task: listening for iCloud account changes")
            for await _ in NotificationCenter.default.notifications(named: PersistenceController.accountDidChange) {
                guard !Task.isCancelled else { break }
                await authViewModel.refetchOnAccountChange()
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

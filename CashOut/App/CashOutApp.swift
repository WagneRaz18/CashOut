import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CashOutApp")

@main
struct CashOutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    let persistenceController = PersistenceController.shared
    @State private var authViewModel = AuthenticationViewModel()
    @State private var showSplash = true

    /// Minimum splash duration so the branding animation completes.
    private static let splashDuration: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds

    private static func seedCategories() async {
        do {
            try await CategoryRepository.shared.seedDefaultCategoriesIfNeeded()
            logger.info("Category seeding completed")
        } catch {
            logger.error("Category seeding failed: \(error.localizedDescription)")
        }

        // Clean up duplicate defaults left by prior seeding failures or CloudKit sync.
        // Runs independently — purge has its own privatePersistentStore guard.
        do {
            try CategoryRepository.shared.purgeDuplicateDefaults()
        } catch {
            logger.error("Category duplicate purge failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showSplash {
                    SplashView()
                } else if authViewModel.isAuthenticated {
                    ContentView()
                        .transition(.opacity)
                } else {
                    SignInView(viewModel: authViewModel)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: showSplash)
            .environment(authViewModel)
            .preferredColorScheme(.dark)
            .environment(
                \.managedObjectContext,
                persistenceController.container.viewContext
            )
            .task {
                // Defer guarantees the splash dismisses even if the task is
                // cancelled mid-startup (e.g., app backgrounded during launch).
                defer { showSplash = false }
                logger.info("App startup task: seeding categories + checking auth")

                // Run splash timer, category seeding, auth check, and history purge concurrently.
                // Splash stays visible until all complete.
                async let splash: Void = Task.sleep(nanoseconds: Self.splashDuration)
                async let seeding: Void = Self.seedCategories()
                async let auth: Void = authViewModel.checkAuth()
                async let purge: Void = persistenceController.purgeOldHistory()
                _ = try? await (splash, seeding, auth, purge)

                logger.info("App startup task complete — authenticated: \(self.authViewModel.isAuthenticated)")
            }
            .task {
                // Long-lived iCloud account-change observer. Runs for the app's lifetime;
                // SwiftUI cancels the task when the window group is torn down.
                await persistenceController.observeAccountChanges()
            }
        }
    }
}

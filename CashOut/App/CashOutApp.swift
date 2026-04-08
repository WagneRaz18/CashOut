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
            .preferredColorScheme(.dark)
            .environment(
                \.managedObjectContext,
                persistenceController.container.viewContext
            )
            .task {
                logger.info("App startup task: seeding categories + checking auth")

                // Run splash timer, category seeding, and auth check concurrently.
                // Splash stays visible until all three complete.
                async let splash: Void = Task.sleep(nanoseconds: Self.splashDuration)
                async let seeding: Void = {
                    guard persistenceController.privatePersistentStore != nil else {
                        logger.error("Skipping category seeding — private store failed to load")
                        return
                    }
                    do {
                        try await CategoryRepository.shared.seedDefaultCategoriesIfNeeded()
                        logger.info("Category seeding completed")
                    } catch {
                        logger.error("Category seeding failed: \(error.localizedDescription)")
                    }
                }()
                async let auth: Void = authViewModel.checkAuth()
                _ = try? await (splash, seeding, auth)

                logger.info("App startup task complete — authenticated: \(self.authViewModel.isAuthenticated)")
                showSplash = false
            }
        }
    }
}

import SwiftUI

@main
struct CashOutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    let persistenceController = PersistenceController.shared
    @State private var authViewModel = AuthenticationViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if authViewModel.isCheckingCredentials {
                    // Invisible placeholder while checking cached credentials.
                    // getCredentialState is a local Keychain + Apple ID cache check (not network),
                    // so this is near-instant — no loading spinner needed (NFR1).
                    Color.clear
                } else if authViewModel.isAuthenticated {
                    ContentView()
                } else {
                    SignInView(viewModel: authViewModel)
                }
            }
            .preferredColorScheme(.dark)
            .environment(
                \.managedObjectContext,
                persistenceController.container.viewContext
            )
            .task {
                async let seeding: Void = {
                    do {
                        try await CategoryRepository().seedDefaultCategoriesIfNeeded()
                    } catch {
                        print("Category seeding failed: \(error)")
                    }
                }()
                async let auth: Void = authViewModel.checkAuth()
                _ = await (seeding, auth)
            }
        }
    }
}

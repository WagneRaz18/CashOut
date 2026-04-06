import UIKit
import CloudKit
import os.log

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // NSPersistentCloudKitContainer processes silent pushes automatically via
        // NSPersistentStoreRemoteChangeNotificationPostOptionKey.
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.sharedPersistentStore else {
            Logger(subsystem: "com.wagneraz.CashOut", category: "AppDelegate")
                .error("Share acceptance failed: shared store unavailable (iCloud may be signed out)")
            return
        }
        persistence.container.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { _, error in
            if let error {
                Logger(subsystem: "com.wagneraz.CashOut", category: "AppDelegate")
                    .error("Error accepting share: \(error.localizedDescription)")
            }
        }
    }
}

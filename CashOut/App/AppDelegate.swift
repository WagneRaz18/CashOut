import UIKit
import CloudKit

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
        // NSPersistentStoreRemoteChangeNotificationPostOptionKey. Calling the
        // completion handler is required so the system knows the fetch is done.
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let container = PersistenceController.shared.container
        let stores = container.persistentStoreCoordinator.persistentStores
        // The shared store is added second in PersistenceController init —
        // identify it by its URL containing "shared".
        guard let sharedStore = stores.first(where: {
            $0.url?.lastPathComponent.contains("shared") ?? false
        }) ?? stores.last else {
            return
        }
        container.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { _, error in
            if let error {
                print("Error accepting share: \(error)")
            }
        }
    }
}

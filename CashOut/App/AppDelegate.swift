import UIKit
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "AppDelegate")

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        logger.info("didFinishLaunchingWithOptions — registering for remote notifications")
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.debug("didReceiveRemoteNotification — silent push received")
        // NSPersistentCloudKitContainer processes silent pushes automatically via
        // NSPersistentStoreRemoteChangeNotificationPostOptionKey.
        completionHandler(.newData)
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        logger.info("userDidAcceptCloudKitShareWith — processing share invitation")
        let persistence = PersistenceController.shared
        guard let sharedStore = persistence.sharedPersistentStore else {
            logger.error("Share acceptance failed: shared store unavailable (iCloud may be signed out)")
            return
        }
        persistence.container.acceptShareInvitations(
            from: [cloudKitShareMetadata],
            into: sharedStore
        ) { _, error in
            // Thread note: CloudKit delivers this completion on an internal serial
            // queue, NOT the main actor — even though the enclosing AppDelegate is
            // @MainActor. `Logger` is thread-safe so os_log calls below are fine,
            // but any access to @MainActor-isolated state must be inside the
            // `Task { @MainActor in }` hop below.
            if let error {
                logger.error("Error accepting share: \(error.localizedDescription)")
            } else {
                logger.info("Share invitation accepted successfully")
                Task { @MainActor in
                    await CloudSharingService.shared.checkSharingStatus()
                }
            }
        }
    }
}

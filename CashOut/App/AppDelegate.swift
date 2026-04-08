import UIKit
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "AppDelegate")

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

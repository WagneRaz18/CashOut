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

    /// Fallback acceptance handler. In normal operation the iOS 14+ scene-based
    /// lifecycle routes CKShare acceptance to `CashOutSceneDelegate.windowScene(
    /// _:userDidAcceptCloudKitShareWith:)` and this method never fires. It is
    /// retained as defense in depth so a future refactor that drops the
    /// `UIApplicationSceneManifest` entry from Info.plist fails loudly (log line
    /// below) instead of silently dropping invitations the way the pre-fix code
    /// did. Acceptance logic itself is owned by `CloudSharingService` — both
    /// entry paths route through the same helper so behavior stays in lockstep.
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        logger.warning("application.userDidAcceptCloudKitShareWith fired (fallback path — scene manifest may be missing)")
        Task { @MainActor in
            await CloudSharingService.shared.handleAcceptedShareMetadata(
                cloudKitShareMetadata,
                entryPath: "appDelegate"
            )
        }
    }
}

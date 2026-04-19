import UIKit
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

    /// Silent-push handler for CloudKit public-DB `CKQuerySubscription` notifications.
    /// Each push tells the app that another paired device wrote a record matching our
    /// household code. We return `.newData` eagerly so we never exceed iOS's 30-second
    /// background execution budget on a large fetch — the debounced fetch runs in the
    /// detached task independently.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        logger.debug("didReceiveRemoteNotification — silent push received, routing to PublicSyncService")
        Task { @MainActor in
            await PublicSyncService.shared.handleRemoteNotification(userInfo: userInfo)
        }
        // Eager acknowledgment — the OS budgets background time against this handler,
        // so we must not block on the full fetch+merge round trip.
        completionHandler(.newData)
    }
}

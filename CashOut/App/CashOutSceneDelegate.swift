import UIKit
import CloudKit
import os.log

private let logger = Logger(subsystem: "com.wagneraz.CashOut", category: "CashOutSceneDelegate")

/// Scene-lifecycle CKShare acceptance handler.
///
/// SwiftUI `@main` + `WindowGroup` implicitly creates a `UIWindowScene` on iOS 13+.
/// In that configuration, Apple routes `userDidAcceptCloudKitShareWith` to the
/// scene delegate's `windowScene(_:userDidAcceptCloudKitShareWith:)`, NOT the
/// AppDelegate's `application(_:userDidAcceptCloudKitShareWith:)`. Without this
/// class wired via `UIApplicationSceneManifest` in Info.plist, CKShare invitations
/// are silently dropped: the system launches the app but no acceptance callback
/// fires. The symptom on the partner's device is a "solo" state that never
/// transitions to `.connected` even after force-quit + relaunch — the shared
/// store never receives the imported CKShare because the acceptance call never
/// runs.
///
/// The AppDelegate's copy of the same method is retained as a defensive fallback
/// (defense in depth if the scene manifest is misconfigured by a future refactor);
/// iOS will call exactly one of the two handlers per acceptance, not both.
/// `@objc(CashOutSceneDelegate)` pins the Objective-C runtime name of this class
/// to the literal string `CashOutSceneDelegate`, independent of Swift module
/// mangling. Without this, the ObjC runtime exposes the class under the
/// module-prefixed form `CashOut.CashOutSceneDelegate`, and Info.plist's
/// `UISceneDelegateClassName` must exactly match. A single space, build-setting
/// variable mis-expansion, or module rename silently breaks class lookup and
/// iOS falls back to a default scene delegate that never calls our acceptance
/// method — the symptom is the app launching on a CKShare tap but no
/// `userDidAcceptCloudKitShareWith` delegate firing at all.
@MainActor
@objc(CashOutSceneDelegate)
final class CashOutSceneDelegate: NSObject, UIWindowSceneDelegate {

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        logger.info("windowScene.userDidAcceptCloudKitShareWith fired — routing to CloudSharingService")
        Task { @MainActor in
            await CloudSharingService.shared.handleAcceptedShareMetadata(
                cloudKitShareMetadata,
                entryPath: "scene"
            )
        }
    }
}

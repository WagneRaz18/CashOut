import SwiftUI
import CloudKit
import os

/// SwiftUI bridge for `UICloudSharingController` with a robust dismiss model.
///
/// Industry-standard CloudKit sharing dismissal has four possible outcomes:
/// 1. `cloudSharingControllerDidSaveShare` — invitation dispatched or permissions changed.
/// 2. `cloudSharingControllerDidStopSharing` — owner tapped Stop Sharing (UIKit auto-deletes
///    the CKShare remotely before the delegate fires).
/// 3. `cloudSharingController(_:failedToSaveShareWithError:)` — save round-trip failed.
/// 4. Interactive swipe/tap-away dismissal — NONE of the above delegate methods fire.
///
/// UIKit exposes the fourth case only through `UIAdaptivePresentationControllerDelegate`,
/// specifically `presentationControllerDidDismiss`. This is the only way to detect a
/// swipe-dismiss reliably; SwiftUI's `.sheet(onDismiss:)` fires unconditionally on every
/// dismissal path and races the UIKit delegate callbacks. Relying on it for swipe detection
/// creates ordering ambiguity.
///
/// The `Coordinator` therefore conforms to BOTH delegate protocols and routes all four
/// paths through a single `fireDismissOnce` entry point that the ViewModel observes as
/// one unified callback: `(CKShare?) -> Void`.
///
/// **Critical wiring note:** `vc.presentationController` is nil inside
/// `makeUIViewController` because UIKit creates the presentation controller lazily, only
/// when SwiftUI actually presents the view controller. Setting the delegate there
/// silently does nothing. It must be wired in `updateUIViewController`, which runs after
/// presentation has occurred.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDismiss: @MainActor (CKShare?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDismiss: onDismiss)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.modalPresentationStyle = .formSheet
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // presentationController is populated AFTER SwiftUI presents the controller, so
        // we wire the delegate here rather than in makeUIViewController. Without this,
        // the swipe-dismiss path is silently inert.
        uiViewController.presentationController?.delegate = context.coordinator
    }

    @MainActor
    final class Coordinator: NSObject,
        UICloudSharingControllerDelegate,
        UIAdaptivePresentationControllerDelegate {

        private let onDismiss: @MainActor (CKShare?) -> Void
        private var dismissHandled = false

        init(onDismiss: @escaping @MainActor (CKShare?) -> Void) {
            self.onDismiss = onDismiss
        }

        // MARK: - UICloudSharingControllerDelegate

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            os_log(.error, "CloudSharingSheet: failedToSaveShare — %{public}@", error.localizedDescription)
            fireDismissOnce(nil)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            // Note: this can fire on permissions changes AND on invite dispatch — it is
            // NOT a reliable "invite sent" signal on its own. The service's
            // `finalizeShareOutcome` classifies the outcome from the share's participants.
            fireDismissOnce(csc.share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            // UIKit has already deleted the CKShare from CloudKit at this point.
            // The service's Stop Sharing path just refreshes state from stores.
            fireDismissOnce(nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            "CashOut Household"
        }

        // MARK: - UIAdaptivePresentationControllerDelegate

        /// Fires on interactive (gesture) dismissal only. Not called when the sheet is
        /// dismissed programmatically (e.g., after `didSaveShare` internally dismisses
        /// the sheet), so there is no double-fire risk with the delegate methods above —
        /// they always fire first and set `dismissHandled = true` via `fireDismissOnce`.
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            fireDismissOnce(nil)
        }

        // MARK: - Idempotency

        /// Routes all dismissal paths through a single entry. Setting `dismissHandled`
        /// BEFORE invoking the callback prevents re-entrancy if the closure synchronously
        /// triggers a re-render that somehow fires another dismiss path.
        private func fireDismissOnce(_ share: CKShare?) {
            guard !dismissHandled else { return }
            dismissHandled = true
            onDismiss(share)
        }
    }
}

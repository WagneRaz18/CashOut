import SwiftUI
import CloudKit
import os

struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onDismiss: (CKShare?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDismiss: onDismiss) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onDismiss: (CKShare?) -> Void

        init(onDismiss: @escaping (CKShare?) -> Void) { self.onDismiss = onDismiss }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            os_log(.error, "Share save failed: %{public}@", error.localizedDescription)
            onDismiss(nil)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onDismiss(csc.share)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onDismiss(nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { "CashOut Household" }
    }
}

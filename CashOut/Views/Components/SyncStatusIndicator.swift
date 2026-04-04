import SwiftUI

struct SyncStatusIndicator: View {
    let syncStatus: SyncStatus

    var body: some View {
        switch syncStatus {
        case .healthy:
            EmptyView()
        case .syncFailure:
            Image(systemName: "exclamationmark.icloud")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sync issue detected")
        case .noICloudAccount:
            EmptyView() // Handled by ICloudBannerView
        }
    }
}

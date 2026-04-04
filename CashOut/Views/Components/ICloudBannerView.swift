import SwiftUI

struct ICloudBannerView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "icloud.slash")
                .font(.subheadline)
                .accessibilityHidden(true)
            Text("Sign in to iCloud to sync")
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sign in to iCloud to sync")
    }
}

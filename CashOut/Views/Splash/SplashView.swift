import SwiftUI

/// Animated splash screen matching the Stitch "Aligned Splash Screen" design.
/// Shows the app icon, title, tagline, and creator credit with staggered fade-in animations.
struct SplashView: View {
    @State private var showIcon = false
    @State private var showTitle = false
    @State private var showTagline = false
    @State private var showCredit = false

    var body: some View {
        ZStack {
            Surface.base.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon container
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Surface.containerHigh)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Image(systemName: "wallet.bifold")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundStyle(SemanticColor.primary)
                    )
                    .shadow(color: SemanticColor.primary.opacity(0.15), radius: 20, y: 8)
                    .scaleEffect(showIcon ? 1.0 : 0.85)
                    .opacity(showIcon ? 1.0 : 0.0)

                // App name
                Text("CashOut")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(SemanticColor.onSurface)
                    .padding(.top, 20)
                    .scaleEffect(showTitle ? 1.0 : 0.85)
                    .opacity(showTitle ? 1.0 : 0.0)

                // Tagline
                Text("THE SILENT STEWARD")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(SemanticColor.onSurfaceVariant.opacity(0.7))
                    .padding(.top, 8)
                    .opacity(showTagline ? 1.0 : 0.0)

                Spacer()

                // Creator credit
                Text("created by WagneRaz")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(SemanticColor.onSurfaceVariant.opacity(0.35))
                    .padding(.bottom, 32)
                    .opacity(showCredit ? 1.0 : 0.0)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                showIcon = true
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                showTagline = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showCredit = true
            }
        }
    }
}

#Preview {
    SplashView()
        .preferredColorScheme(.dark)
}

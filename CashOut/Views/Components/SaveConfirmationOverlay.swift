import SwiftUI

enum SaveAnimationPhase: CaseIterable {
    case hidden
    case visible
    case fadeOut
}

struct SaveConfirmationOverlay: View {
    let trigger: Int

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64
    private static let phases = SaveAnimationPhase.allCases

    var body: some View {
        PhaseAnimator(Self.phases, trigger: trigger) { phase in
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(SemanticColor.success)
                .opacity(phase == .visible && trigger > 0 ? 1 : 0)
                .scaleEffect(scaleFor(phase))
        } animation: { phase in
            switch phase {
            case .hidden: .easeOut(duration: 0.15)
            case .visible: .easeOut(duration: 0.2)
            case .fadeOut: .easeOut(duration: 0.3).delay(0.4)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func scaleFor(_ phase: SaveAnimationPhase) -> CGFloat {
        switch phase {
        case .hidden: 0.5
        case .visible: 1.0
        case .fadeOut: 1.1
        }
    }
}

#Preview {
    @Previewable @State var trigger = 0
    VStack(spacing: 40) {
        Text("฿1,250")
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .overlay {
                SaveConfirmationOverlay(trigger: trigger)
            }

        Button("Trigger") { trigger += 1 }
            .buttonStyle(.borderedProminent)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black)
}

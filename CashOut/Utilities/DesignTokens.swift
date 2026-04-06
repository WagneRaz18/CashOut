import SwiftUI

// MARK: - Surface Palette (Stitch "Utilitarian Ether" design system)

/// Layered surface colors for depth without borders.
/// Base → Container Low → Container → Container High → Container Highest
/// Dark-only surface palette. App enforces dark mode via .preferredColorScheme(.dark).
enum Surface {
    static let base = Color(hex: 0x040E1F)
    static let containerLowest = Color(hex: 0x000000)
    static let containerLow = Color(hex: 0x02132C)
    static let container = Color(hex: 0x001938)
    static let containerHigh = Color(hex: 0x001F43)
    static let containerHighest = Color(hex: 0x00264E)
    static let bright = Color(hex: 0x002C5A)
    static let variant = Color(hex: 0x00264E)
    static let tint = Color(hex: 0xAAC9F0)
}

// MARK: - Semantic Colors

enum SemanticColor {
    // Primary
    static let primary = Color(hex: 0xAAC9F0)
    static let primaryContainer = Color(hex: 0x294969)
    static let primaryDim = Color(hex: 0x9CBBE2)
    static let onPrimary = Color(hex: 0x214262)
    static let onPrimaryContainer = Color(hex: 0xB3D3FA)

    // Secondary
    static let secondary = Color(hex: 0x909FB4)
    static let secondaryContainer = Color(hex: 0x2E3C4E)
    static let onSecondary = Color(hex: 0x122131)
    static let onSecondaryContainer = Color(hex: 0xB1C0D6)

    // Tertiary
    static let tertiary = Color(hex: 0xB4C1FF)
    static let tertiaryContainer = Color(hex: 0xA3B2FA)
    static let onTertiary = Color(hex: 0x2A3A79)

    // On-Surface text
    static let onSurface = Color(hex: 0xDAE6FF)
    static let onSurfaceVariant = Color(hex: 0x89ACE7)
    static let onBackground = Color(hex: 0xDAE6FF)

    // Outline
    static let outline = Color(hex: 0x5376AE)
    static let outlineVariant = Color(hex: 0x21487D)

    // Error
    static let error = Color(hex: 0xEE7D77)
    static let errorDim = Color(hex: 0xBB5551)
    static let errorContainer = Color(hex: 0x7F2927)
    static let onError = Color(hex: 0x490106)

    // Inverse
    static let inverseSurface = Color(hex: 0xF9F9FF)
    static let inverseOnSurface = Color(hex: 0x4A5569)
    static let inversePrimary = Color(hex: 0x426183)
}

// MARK: - Glass Effect

/// Glassmorphism modifier matching Stitch design: tinted color layer + frosted material on top.
struct GlassBackground: ViewModifier {
    var opacity: Double = 0.4

    func body(content: Content) -> some View {
        content
            .background(SemanticColor.primaryContainer.opacity(opacity))
            .background(.ultraThinMaterial)
    }
}

extension View {
    func glassBackground(opacity: Double = 0.4) -> some View {
        modifier(GlassBackground(opacity: opacity))
    }
}

// MARK: - Color Hex Initializer

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}

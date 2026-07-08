import SwiftUI
import UIKit

/// Centralized color palette for Hetzly. Dark is the hero mode (near-black
/// canvas, single sparing accent) and is pixel-identical to the original
/// dark-only palette; light is an adaptive variant per CONTRACTS.md. Canvas
/// and text colors are trait-adaptive `UIColor`-backed `Color`s that track
/// `\.colorScheme`/system appearance live; accent, destructive, and status
/// colors are identical in both modes by contract, so they stay plain
/// hex `Color`s.
enum HetzlyColors {
    static let canvas = adaptive(dark: 0x0A0A0C, light: 0xF5F5F7)
    static let accent = Color(hex: 0xF0483E)
    static let destructive = Color(hex: 0xFF5C5C)

    static let textPrimary = adaptive(dark: 0xF5F5F7, light: 0x1D1D1F)
    static let textSecondary = adaptive(dark: 0x9A9AA2, light: 0x6E6E73)
    static let textTertiary = adaptive(dark: 0x5A5A63, light: 0xAEAEB2)

    static let statusRunning = Color(hex: 0x30D158)
    static let statusOff = Color(hex: 0x5A5A63)
    static let statusTransitioning = Color(hex: 0xFFD60A)
    static let statusError = Color(hex: 0xFF453A)

    /// Reduce-transparency / non-glass fallback fill shared by
    /// `GlassCard`/`GlassChip`/`GlassSurface` and the handful of feature
    /// views that hand-roll the same fallback chrome (glass capsule chips
    /// with a solid-fill fallback). Dark stays the original `Color(white:
    /// 0.12)`; light is the contract's "0.88-ish" near-white fill.
    static let glassFallbackFill = grayscaleAdaptive(dark: 0.12, light: 0.88)

    /// Companion hairline stroke for `glassFallbackFill`. Dark stays the
    /// original `Color.white.opacity(0.08)`; light uses a dark hairline at
    /// the same magnitude so the edge stays legible against a light fill.
    static let glassFallbackStroke = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.08)
    })

    /// Full-bleed footer variant of `glassFallbackFill` (slightly deeper in
    /// dark, slightly deeper in light too) — `GlassSurface`'s
    /// `glassFooterBackground()` fallback.
    static let glassFallbackFillDeep = grayscaleAdaptive(dark: 0.09, light: 0.91)

    /// Builds a `Color` that resolves to `dark` hex under dark appearance
    /// and `light` hex under light appearance, tracking the environment's
    /// trait collection (and therefore `Settings → Appearance → System`)
    /// live — unlike a plain `Color(hex:)`, which is static.
    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(hex: light) : UIColor(hex: dark)
        })
    }

    /// Same as `adaptive(dark:light:)` but for grayscale fill colors
    /// expressed the same way the original hard-coded `Color(white:)`
    /// fallbacks were.
    private static func grayscaleAdaptive(dark: CGFloat, light: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light
                ? UIColor(white: light, alpha: 1)
                : UIColor(white: dark, alpha: 1)
        })
    }
}

extension Color {
    /// Builds a `Color` from a 24-bit RGB hex literal, e.g. `0x0A0A0C`.
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

private extension UIColor {
    /// Builds a `UIColor` from a 24-bit RGB hex literal — the `UIColor`
    /// counterpart to `Color(hex:)`, needed inside the `UIColor { traits in
    /// ... }` dynamic-provider closures above (those must return `UIColor`,
    /// not `Color`).
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(
            [
                ("canvas", HetzlyColors.canvas),
                ("accent", HetzlyColors.accent),
                ("destructive", HetzlyColors.destructive),
                ("textPrimary", HetzlyColors.textPrimary),
                ("textSecondary", HetzlyColors.textSecondary),
                ("textTertiary", HetzlyColors.textTertiary),
                ("statusRunning", HetzlyColors.statusRunning),
                ("statusOff", HetzlyColors.statusOff),
                ("statusTransitioning", HetzlyColors.statusTransitioning),
                ("statusError", HetzlyColors.statusError),
            ],
            id: \.0
        ) { name, color in
            HStack {
                RoundedRectangle(cornerRadius: 6).fill(color).frame(width: 32, height: 32)
                Text(name).foregroundStyle(.white)
            }
        }
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

import SwiftUI

/// Local copy of the values in `Hetzly/DesignSystem/HetzlyColors.swift`.
/// The widget extension is a separate module and can't import app-target
/// code, so the small set of colors it actually needs is replicated here
/// rather than shared — see CONTRACTS.md.
enum WidgetColors {
    static let canvas = Color(widgetHex: 0x0A0A0C)
    static let accent = Color(widgetHex: 0xF0483E)

    static let textPrimary = Color(widgetHex: 0xF5F5F7)
    static let textSecondary = Color(widgetHex: 0x9A9AA2)
    static let textTertiary = Color(widgetHex: 0x5A5A63)

    static let statusRunning = Color(widgetHex: 0x30D158)
    static let statusOff = Color(widgetHex: 0x5A5A63)
    static let statusTransitioning = Color(widgetHex: 0xFFD60A)
    static let statusError = Color(widgetHex: 0xFF453A)

    /// Maps a `HetznerKit.ServerStatus.rawValue` string to the same coarse
    /// bucketing `Hetzly/Features/Dashboard/DashboardSupport.swift` uses,
    /// without depending on that enum (the widget only ever sees a `String`
    /// via `WidgetSnapshot.ServerSummary.statusRaw`).
    static func statusColor(forRaw raw: String) -> Color {
        switch raw {
        case "running":
            statusRunning
        case "off":
            statusOff
        case "initializing", "starting", "stopping", "deleting", "migrating", "rebuilding":
            statusTransitioning
        default:
            textTertiary
        }
    }
}

private extension Color {
    /// Builds a `Color` from a 24-bit RGB hex literal, e.g. `0x0A0A0C`.
    /// Named distinctly from the app target's `Color(hex:)` (different
    /// module, but kept unambiguous for anyone reading both side by side).
    init(widgetHex hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, opacity: opacity)
    }
}

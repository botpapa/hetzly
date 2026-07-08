import SwiftUI

/// Centralized color palette for Hetzly. Dark-first, near-black canvas with a
/// single sparing accent. Values match the design contract in CONTRACTS.md.
enum HetzlyColors {
    static let canvas = Color(hex: 0x0A0A0C)
    static let accent = Color(hex: 0xF0483E)
    static let destructive = Color(hex: 0xFF5C5C)

    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0x9A9AA2)
    static let textTertiary = Color(hex: 0x5A5A63)

    static let statusRunning = Color(hex: 0x30D158)
    static let statusOff = Color(hex: 0x5A5A63)
    static let statusTransitioning = Color(hex: 0xFFD60A)
    static let statusError = Color(hex: 0xFF453A)
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

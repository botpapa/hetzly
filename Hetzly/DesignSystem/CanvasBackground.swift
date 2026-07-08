import SwiftUI

/// Near-black (dark) / soft off-white (light) app canvas with a
/// barely-perceptible radial depth gradient so content never sits on a flat
/// fill. Dark mode is pixel-identical to the original dark-only version.
struct CanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    /// Dark: a hair *lighter* than `canvas`. Light: a hair *darker* than
    /// `canvas` (#F5F5F7) — mirrors the same 2-3% lightness delta so the
    /// depth cue stays equally barely-perceptible in both directions.
    private var core: Color {
        colorScheme == .dark ? Color(hex: 0x111114) : Color(hex: 0xECECEF)
    }

    var body: some View {
        ZStack {
            HetzlyColors.canvas

            RadialGradient(
                colors: [core, HetzlyColors.canvas],
                center: .center,
                startRadius: 0,
                endRadius: 640
            )
        }
        .ignoresSafeArea()
    }
}

#Preview {
    CanvasBackground()
        .preferredColorScheme(.dark)
}

#Preview("Appearance: Light") {
    CanvasBackground()
        .preferredColorScheme(.light)
}

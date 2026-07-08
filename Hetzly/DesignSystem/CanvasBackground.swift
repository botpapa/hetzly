import SwiftUI

/// Near-black app canvas with a barely-perceptible radial depth gradient so
/// content never sits on flat black.
struct CanvasBackground: View {
    /// A hair lighter than `canvas` — keeps the radial falloff to a 2-3%
    /// lightness delta so the depth cue stays barely perceptible.
    private static let core = Color(hex: 0x111114)

    var body: some View {
        ZStack {
            HetzlyColors.canvas

            RadialGradient(
                colors: [Self.core, HetzlyColors.canvas],
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

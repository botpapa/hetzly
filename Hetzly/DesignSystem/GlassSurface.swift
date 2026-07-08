import SwiftUI

/// Shared Liquid Glass surface: applies a real `.glassEffect` normally, but
/// falls back to a solid fill + hairline border when
/// `accessibilityReduceTransparency` is enabled. `GlassCard`/`GlassChip`
/// each implement this fallback pattern locally (they predate this helper
/// and have their own layout needs); this exists for the smaller one-off
/// glass surfaces scattered across feature views — segmented pickers,
/// toasts, circular action buttons — so they don't each hand-roll the same
/// conditional.
struct GlassSurfaceModifier<S: InsettableShape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let shape: S
    var interactive: Bool = false

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background {
                shape
                    .fill(HetzlyColors.glassFallbackFill)
                    .overlay { shape.strokeBorder(HetzlyColors.glassFallbackStroke, lineWidth: 1) }
            }
        } else {
            content.glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
        }
    }
}

extension View {
    /// Applies a Liquid Glass surface clipped to `shape`, with an automatic
    /// solid fallback when Reduce Transparency is enabled.
    func glassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurfaceModifier(shape: shape, interactive: interactive))
    }

    /// A full-bleed glass bar anchored to the bottom safe area (wizard step
    /// footers), with a solid fallback when Reduce Transparency is enabled.
    func glassFooterBackground() -> some View {
        modifier(GlassFooterBackgroundModifier())
    }
}

private struct GlassFooterBackgroundModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                HetzlyColors.glassFallbackFillDeep.ignoresSafeArea(edges: .bottom)
            } else {
                Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 0)).ignoresSafeArea(edges: .bottom)
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            Text("Segmented")
                .bodySecondary()
                .padding(.horizontal, Spacing.unit * 3)
                .padding(.vertical, Spacing.unit * 1.5)
                .glassSurface(Capsule(style: .continuous))

            Image(systemName: "power")
                .frame(width: 44, height: 44)
                .glassSurface(Circle(), interactive: true)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

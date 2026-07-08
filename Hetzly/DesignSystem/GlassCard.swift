import SwiftUI

/// A card surface rendered with Liquid Glass (`.glassEffect(.regular, in:)`).
/// Falls back to a solid dark fill with a hairline border when
/// `accessibilityReduceTransparency` is enabled.
struct GlassCard<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let interactive: Bool
    private let content: Content

    init(interactive: Bool = false, @ViewBuilder content: () -> Content) {
        self.interactive = interactive
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
    }

    var body: some View {
        content
            .padding(Spacing.cardPadding)
            .background {
                if reduceTransparency {
                    shape
                        .fill(Color(white: 0.12))
                        .overlay {
                            shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                        }
                } else {
                    Color.clear
                }
            }
            .modifier(GlassCardEffect(interactive: interactive, shape: shape, isEnabled: !reduceTransparency))
    }
}

/// Applies `.glassEffect` only when transparency is allowed, keeping the
/// conditional out of the view builder above (glassEffect's `in:` generic
/// shape parameter makes an `if/else` branch there awkward to type-check).
private struct GlassCardEffect: ViewModifier {
    let interactive: Bool
    let shape: RoundedRectangle
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.glassEffect(interactive ? Glass.regular.interactive() : .regular, in: shape)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text("cx22 · nbg1-dc3").bodyPrimary()
                    Text("2 vCPU · 4 GB RAM · 40 GB").bodySecondary()
                }
            }
            GlassCard(interactive: true) {
                Text("Interactive card").bodyPrimary()
            }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

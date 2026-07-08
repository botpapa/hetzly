import SwiftUI

/// Documents Hetzly's two button-style conventions on top of the system
/// Liquid Glass styles. This type carries no state — it exists so the
/// convention has one discoverable home; prefer the `PrimaryCTA` /
/// `DestructiveCTA` convenience views or the `View` helpers below directly.
///
/// - Primary CTA: `.buttonStyle(.glassProminent)` tinted with `HetzlyColors.accent`.
/// - Secondary action: plain `.buttonStyle(.glass)`, no tint override.
enum GlassCTAButtonStyle {}

extension View {
    /// Primary call-to-action styling: prominent glass, brand-accent tinted.
    func primaryCTAStyle() -> some View {
        self.buttonStyle(.glassProminent).tint(HetzlyColors.accent)
    }

    /// Secondary action styling: regular (non-prominent) glass.
    func secondaryCTAStyle() -> some View {
        self.buttonStyle(.glass)
    }
}

/// The app's primary call-to-action button: prominent glass, accent-tinted.
struct PrimaryCTA: View {
    let title: String
    let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .primaryCTAStyle()
    }
}

/// A destructive action button: prominent glass, tinted with
/// `HetzlyColors.destructive`. Callers should pair destructive actions with
/// `.sensoryFeedback(.warning, trigger:)` on the confirming state change.
struct DestructiveCTA: View {
    let title: String
    let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.glassProminent)
            .tint(HetzlyColors.destructive)
    }
}

#Preview("CTAs") {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            PrimaryCTA(title: "Create Server") {}
            DestructiveCTA(title: "Delete Server") {}
            Button("Cancel") {}
                .secondaryCTAStyle()
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

/// Validates `GlassEffectContainer` + `glassEffectID`: a row of circular
/// glass action buttons that visually merge when placed close together.
private struct GlassActionRow: View {
    @Namespace private var namespace
    @State private var showExtra = false

    var body: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                circularButton(systemImage: "power", id: "power")
                circularButton(systemImage: "arrow.clockwise", id: "restart")
                if showExtra {
                    circularButton(systemImage: "trash", id: "trash")
                }
            }
        }
        .onTapGesture { showExtra.toggle() }
    }

    private func circularButton(systemImage: String, id: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(HetzlyColors.textPrimary)
            .frame(width: 44, height: 44)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID(id, in: namespace)
    }
}

#Preview("GlassEffectContainer merge") {
    ZStack {
        CanvasBackground()
        GlassActionRow()
    }
    .preferredColorScheme(.dark)
}

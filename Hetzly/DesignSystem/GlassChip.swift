import SwiftUI

/// A capsule-shaped glass chip with a label and optional leading SF Symbol.
/// Falls back to a solid dark fill when `accessibilityReduceTransparency`
/// is enabled.
struct GlassChip: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let label: String
    var systemImage: String?

    init(_ label: String, systemImage: String? = nil) {
        self.label = label
        self.systemImage = systemImage
    }

    private var capsule: Capsule { Capsule(style: .continuous) }

    var body: some View {
        HStack(spacing: Spacing.unit) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(label)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(HetzlyColors.textPrimary)
        .padding(.horizontal, Spacing.unit * 3)
        .padding(.vertical, Spacing.unit * 1.5)
        .background {
            if reduceTransparency {
                capsule
                    .fill(HetzlyColors.glassFallbackFill)
                    .overlay { capsule.strokeBorder(HetzlyColors.glassFallbackStroke, lineWidth: 1) }
            } else {
                Color.clear
            }
        }
        .modifier(GlassChipEffect(shape: capsule, isEnabled: !reduceTransparency))
    }
}

private struct GlassChipEffect: ViewModifier {
    let shape: Capsule
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.glassEffect(.regular, in: shape)
        } else {
            content
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        HStack(spacing: Spacing.unit * 2) {
            GlassChip("nbg1-dc3", systemImage: "globe")
            GlassChip("Running")
        }
    }
    .preferredColorScheme(.dark)
}

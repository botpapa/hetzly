import SwiftUI

/// A thin, accent-tinted horizontal progress bar for "used vs. capacity"
/// readouts (a Storage Box's total usage against its plan size). Renders
/// nothing but an empty track when `fraction` is `nil` — callers pass `nil`
/// when stats haven't loaded yet rather than faking a value.
struct StorageBoxUsageBar: View {
    /// 0...1, or `nil` when unknown.
    let fraction: Double?

    private let height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))

                if let fraction {
                    Capsule(style: .continuous)
                        .fill(HetzlyColors.accent)
                        .frame(width: geometry.size.width * fraction)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Usage")
        .accessibilityValue(fraction.map { "\(Int($0 * 100)) percent" } ?? "Unknown")
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            StorageBoxUsageBar(fraction: 0.42)
            StorageBoxUsageBar(fraction: 0.91)
            StorageBoxUsageBar(fraction: nil)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

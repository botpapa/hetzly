import SwiftUI

/// The small icon badge shown at the top of gather/confirm sheets across the
/// app (e.g. "Create Snapshot", "Enable Rescue Mode", "Delete Zone") —
/// previously ~17 copy-pasted `Image(systemName:)` blocks, most of them
/// tinted with `HetzlyColors.accent`.
///
/// Per CONTRACTS.md's accent-discipline rule, `HetzlyColors.accent` is
/// reserved for the single primary CTA per screen and running/status dots —
/// nothing else. These header badges are decorative context icons, not
/// calls to action, so the default tint here is neutral
/// (`HetzlyColors.textSecondary`). Pass an explicit `tint` only when the
/// icon itself carries real semantic meaning, e.g.
/// `HetzlyColors.destructive` for a delete/rebuild warning header.
struct SheetHeaderBadge: View {
    let systemImage: String
    var tint: Color = HetzlyColors.textSecondary

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "camera")
                Text("Neutral (default)").bodyPrimary()
            }
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "exclamationmark.triangle.fill", tint: HetzlyColors.destructive)
                Text("Destructive").bodyPrimary()
            }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

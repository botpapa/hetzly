import HetznerKit
import SwiftUI

/// Collapsed-by-default DANGER ZONE disclosure: Rebuild, Rescale, and
/// Delete Server. Rebuild/Delete respect Hetzner's protection flags — when
/// protection is on, the row shows a lock, is disabled, and explains how to
/// unlock. All three hand off to flows owned by `ServerDetailView`
/// (image/type picker sheets, then the shared confirm-sheet +
/// biometric-gate pipeline).
struct ServerDangerZoneSection: View {
    let protection: ServerProtection
    var onRebuild: () -> Void
    var onRescale: () -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            GlassCard {
                VStack(spacing: 0) {
                    row(
                        title: "Rebuild",
                        systemImage: "arrow.triangle.2.circlepath",
                        locked: protection.rebuild,
                        action: onRebuild
                    )
                    divider
                    row(
                        title: "Rescale",
                        systemImage: "arrow.up.left.and.arrow.down.right",
                        locked: false,
                        action: onRescale
                    )
                    divider
                    row(
                        title: "Delete Server",
                        systemImage: "trash",
                        locked: protection.delete,
                        action: onDelete
                    )

                    if protection.delete || protection.rebuild {
                        divider
                        Text("Locked rows are protected. Turn off Deletion Protection above to unlock them.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Spacing.unit * 2)
                    }
                }
            }
            .padding(.top, Spacing.unit * 3)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .tint(HetzlyColors.textTertiary)
    }

    private var divider: some View {
        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
    }

    private func row(
        title: String, systemImage: String, locked: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(HetzlyColors.destructive)
                Spacer()
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.destructive.opacity(0.6))
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
        .opacity(locked ? 0.4 : 1)
        .accessibilityHint(locked ? "\(title) is disabled while deletion protection is on" : "")
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 8) {
            ServerDangerZoneSection(
                protection: ServerProtection(delete: false, rebuild: false),
                onRebuild: {},
                onRescale: {},
                onDelete: {}
            )
            ServerDangerZoneSection(
                protection: ServerProtection(delete: true, rebuild: true),
                onRebuild: {},
                onRescale: {},
                onDelete: {}
            )
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

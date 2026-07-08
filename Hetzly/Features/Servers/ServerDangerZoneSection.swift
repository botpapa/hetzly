import SwiftUI

/// Collapsed-by-default DANGER ZONE disclosure: Rebuild / Rescale (both
/// disabled, tagged "M2") and Delete Server, which hands off to the shared
/// confirm-sheet + biometric-gate flow owned by `ServerDetailView`.
struct ServerDangerZoneSection: View {
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            GlassCard {
                VStack(spacing: 0) {
                    row(title: "Rebuild", systemImage: "arrow.triangle.2.circlepath", badge: "M2")
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                    row(title: "Rescale", systemImage: "arrow.up.left.and.arrow.down.right", badge: "M2")
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                    deleteRow
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

    private func row(title: String, systemImage: String, badge: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .bodyPrimary()
                .foregroundStyle(HetzlyColors.textSecondary)
            Spacer()
            GlassChip(badge)
        }
        .padding(.vertical, Spacing.unit * 2)
        .opacity(0.5)
    }

    private var deleteRow: some View {
        Button(action: onDelete) {
            HStack {
                Label("Delete Server", systemImage: "trash")
                    .foregroundStyle(HetzlyColors.destructive)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.destructive.opacity(0.6))
            }
            .padding(.vertical, Spacing.unit * 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ServerDangerZoneSection(onDelete: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

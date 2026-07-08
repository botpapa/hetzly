import SwiftUI

/// The MANAGE section of `ProjectDetailView`: rename, update the stored API
/// token, and remove the project from Hetzly. Every row just calls back into
/// the parent, which owns the actual alert/sheet/confirmation state (mirrors
/// how `SettingsView` keeps its own project rename/remove state rather than
/// pushing it down into a row view).
struct ProjectManageSection: View {
    let onRename: () -> Void
    let onUpdateToken: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Manage")

            GlassCard {
                VStack(spacing: 0) {
                    row(title: "Rename", systemImage: "pencil", action: onRename)
                    rowDivider
                    row(title: "Update API Token", systemImage: "key", action: onUpdateToken)
                    rowDivider
                    row(title: "Remove from Hetzly", systemImage: "trash", destructive: true, action: onRemove)
                }
            }

            Text("Only removes it from this app — nothing is touched on Hetzner.")
                .caption()
        }
    }

    private var rowDivider: some View {
        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
    }

    private func row(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(destructive ? HetzlyColors.destructive : HetzlyColors.accent)
                    .frame(width: 22)
                Text(title)
                    .bodyPrimary()
                    .foregroundStyle(destructive ? HetzlyColors.destructive : HetzlyColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ProjectManageSection(onRename: {}, onUpdateToken: {}, onRemove: {})
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

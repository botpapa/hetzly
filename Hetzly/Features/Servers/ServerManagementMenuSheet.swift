import HetznerKit
import SwiftUI

/// The "More" sheet opened from the ellipsis button in the action row: a
/// glass list of management actions, contextual to the server's current
/// state (backups/rescue rows flip between enable/disable, ISO row shows
/// attach vs. detach). Selecting an item dismisses the sheet and hands the
/// chosen entry back to `ServerDetailView`, which owns the follow-up flow
/// (confirm sheet, parameter sheet, or direct fire).
struct ServerManagementMenuSheet: View {
    /// What the user picked. Parameter-gathering entries (snapshot, rescue,
    /// ISO) map to dedicated sheets in `ServerDetailView`; the rest map to
    /// the shared management confirm flow.
    enum Selection: Equatable {
        case createSnapshot
        case toggleBackups
        case toggleRescue
        case iso
        case resetRootPassword
        case requestConsole
    }

    let server: Server
    var onSelect: (Selection) -> Void

    @Environment(\.dismiss) private var dismiss

    private var backupsEnabled: Bool { server.backupWindow != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Manage Server")

            GlassCard {
                VStack(spacing: 0) {
                    row(
                        title: "Create Snapshot",
                        subtitle: "Full disk image you can restore later",
                        systemImage: "camera",
                        selection: .createSnapshot
                    )
                    divider
                    row(
                        title: backupsEnabled ? "Disable Backups" : "Enable Backups",
                        subtitle: backupsEnabled
                            ? "Window \(server.backupWindow ?? "")h UTC"
                            : "Daily, adds about 20% to server cost",
                        systemImage: "clock.arrow.circlepath",
                        selection: .toggleBackups
                    )
                    divider
                    row(
                        title: server.rescueEnabled ? "Disable Rescue Mode" : "Enable Rescue Mode",
                        subtitle: server.rescueEnabled
                            ? "Rescue system armed for next boot"
                            : "Minimal recovery system on next boot",
                        systemImage: "lifepreserver",
                        selection: .toggleRescue
                    )
                    divider
                    row(
                        title: "Attach ISO",
                        subtitle: "Boot from a virtual disc image",
                        systemImage: "opticaldiscdrive",
                        selection: .iso
                    )
                    divider
                    row(
                        title: "Reset Root Password",
                        subtitle: "Generates a new one-time password",
                        systemImage: "key",
                        selection: .resetRootPassword
                    )
                    divider
                    row(
                        title: "Request Console",
                        subtitle: "VNC-over-websocket credentials",
                        systemImage: "terminal",
                        selection: .requestConsole
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 4)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private var divider: some View {
        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
    }

    private func row(
        title: String, subtitle: String, systemImage: String, selection: Selection
    ) -> some View {
        Button {
            dismiss()
            onSelect(selection)
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .bodyPrimary()
                    Text(subtitle)
                        .caption()
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2.5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ServerManagementMenuSheet(server: PreviewFixtures.server) { _ in }
    }
}

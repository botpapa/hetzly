import HetznerKit
import SwiftUI

/// Shows every server/label-selector a firewall is currently applied to as
/// removable chips, plus a button that opens `ApplyToServerSheet` to attach
/// more servers. Server names are resolved from `servers` (loaded via
/// `listServers()` by the caller) — falls back to `"Server #id"` if a
/// referenced server can't be found (e.g. it was deleted elsewhere).
struct AppliedToView: View {
    let appliedTo: [FirewallResource]
    let servers: [Server]
    var isSaving: Bool = false
    var onApply: () -> Void
    var onRemoveServer: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            if appliedTo.isEmpty {
                Text("Not applied to anything yet.").bodySecondary()
            } else {
                FlowLayout(spacing: Spacing.unit * 2) {
                    ForEach(Array(appliedTo.enumerated()), id: \.offset) { _, resource in
                        chip(for: resource)
                    }
                }
            }

            Button(action: onApply) {
                Label("Apply to Server", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HetzlyColors.accent)
            .disabled(isSaving)
        }
        .opacity(isSaving ? 0.6 : 1)
    }

    @ViewBuilder
    private func chip(for resource: FirewallResource) -> some View {
        switch resource.type {
        case .server:
            if let serverID = resource.server?.id {
                HStack(spacing: Spacing.unit) {
                    Image(systemName: "server.rack").font(.system(size: 11))
                    Text(serverName(for: serverID)).font(.system(size: 13, weight: .medium))
                    Button { onRemoveServer(serverID) } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                    }
                    .disabled(isSaving)
                }
                .foregroundStyle(HetzlyColors.textPrimary)
                .padding(.horizontal, Spacing.unit * 2.5)
                .padding(.vertical, Spacing.unit * 1.5)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.08)))
            }
        case .labelSelector:
            if let selector = resource.labelSelector?.selector {
                HStack(spacing: Spacing.unit) {
                    Image(systemName: "tag").font(.system(size: 11))
                    Text(selector).font(.system(size: 13, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(HetzlyColors.textSecondary)
                .padding(.horizontal, Spacing.unit * 2.5)
                .padding(.vertical, Spacing.unit * 1.5)
                .background(Capsule(style: .continuous).fill(Color.white.opacity(0.05)))
            }
        case .unknown:
            EmptyView()
        }
    }

    private func serverName(for id: Int) -> String {
        servers.first { $0.id == id }?.name ?? "Server #\(id)"
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        AppliedToView(
            appliedTo: FirewallPreviewFixtures.webFirewall.appliedTo,
            servers: FirewallPreviewFixtures.servers,
            onApply: {},
            onRemoveServer: { _ in }
        )
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

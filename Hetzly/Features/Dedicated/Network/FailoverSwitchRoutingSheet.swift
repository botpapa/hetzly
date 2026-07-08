import HetznerKit
import SwiftUI

/// Step 1 of the "switch routing" flow — the money action for a failover
/// IP: pick a target server (and its address) from the account's dedicated
/// servers. Gathers a selection only; `FailoverDetailView` presents
/// `FailoverRerouteConfirmSheet` next, then gates on biometrics
/// unconditionally before actually calling `switchFailover`.
struct FailoverSwitchRoutingSheet: View {
    let failoverIP: String
    let accountServers: [RobotServer]
    let state: FailoverDetailViewModel.LoadState
    /// `(server, targetIP)`.
    var onSelect: (RobotServer, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header
            serverList
            Spacer(minLength: 0)
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private var header: some View {
        HStack(spacing: Spacing.unit * 3) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HetzlyColors.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Switch Routing")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Text(failoverIP)
                    .hetzlyMonoNumbers()
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var serverList: some View {
        switch state {
        case .idle, .loading:
            HStack(spacing: Spacing.unit * 2) {
                ProgressView()
                Text("Loading servers…").caption()
            }
        case .failed(let message):
            Text(message).caption()
        case .loaded:
            let candidates = accountServers.filter { $0.serverIP != nil }
            if candidates.isEmpty {
                Text("No dedicated servers with an IPv4 address are available to route to.")
                    .bodySecondary()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(candidates.enumerated()), id: \.element.serverNumber) { index, server in
                                if index > 0 {
                                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                                }
                                serverRow(server)
                            }
                        }
                    }
                }
            }
        }
    }

    private func serverRow(_ server: RobotServer) -> some View {
        Button {
            guard let ip = server.serverIP else { return }
            dismiss()
            onSelect(server, ip)
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(server.resourceStatus)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName).bodyPrimary()
                    if let ip = server.serverIP {
                        Text(ip).hetzlyMonoNumbers().font(.system(size: 12, design: .monospaced)).foregroundStyle(HetzlyColors.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Step 2 — the explicit, restate-everything confirmation before the
/// biometric gate. Routing changes are outage-grade: this is the last
/// chance to back out before Face ID/passcode is asked for unconditionally.
struct FailoverRerouteConfirmSheet: View {
    let failoverIP: String
    let targetServerName: String
    let targetIP: String
    var isAuthenticating: Bool = false
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 36, height: 36)
                Text("Confirm Reroute")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Spacer()
            }

            Text(
                "Reroute \(failoverIP) to \(targetServerName) (\(targetIP))? "
                    + "Traffic switches within minutes; the old route stops working."
            )
            .bodySecondary()
            .fixedSize(horizontal: false, vertical: true)

            Label("Face ID / passcode is required to continue — routing changes affect live traffic.", systemImage: "faceid")
                .caption()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel", action: onCancel)
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(isAuthenticating)

                PrimaryCTA(title: isAuthenticating ? "Verifying…" : "Reroute", action: onConfirm)
                    .frame(maxWidth: .infinity)
                    .disabled(isAuthenticating)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

#Preview("Pick server") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        FailoverSwitchRoutingSheet(
            failoverIP: "138.201.22.100",
            accountServers: [DedicatedPreviewFixtures.server, DedicatedPreviewFixtures.inProcessServer],
            state: .loaded
        ) { _, _ in }
    }
}

#Preview("Confirm reroute") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        FailoverRerouteConfirmSheet(
            failoverIP: "138.201.22.100",
            targetServerName: "dedi-prod-01",
            targetIP: "95.216.3.171",
            onConfirm: {},
            onCancel: {}
        )
    }
}

import HetznerKit
import SwiftUI

/// "DEDICATED" section on the dashboard: every Robot dedicated server across
/// every configured Robot account. Only rendered by the parent when there's
/// something to show (servers and/or an error) — i.e. only once at least one
/// Robot account exists, since `DashboardViewModel.dedicatedServers` /
/// `.dedicatedError` stay empty/nil otherwise.
///
/// Rows are `NavigationLink`s carrying a `RobotServerRoute`
/// (`Features/Dedicated`'s own route type — the dashboard's `DashboardView`
/// declares the matching `.navigationDestination(for: RobotServerRoute.self)`
/// so the push lands on `DedicatedServerDetailView`).
struct DedicatedSectionView: View {
    let servers: [DashboardViewModel.DedicatedServerItem]
    let errorMessage: String?
    /// `true` when `errorMessage` came from bad Robot account credentials.
    /// Robot has no per-project token to swap in place like Cloud does, so
    /// this shows a hint pointing at Settings rather than an "Update
    /// token…" sheet that doesn't exist for Robot. Defaulted so existing
    /// call sites (previews) keep compiling unchanged.
    var isAuthError = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Dedicated")

            if let errorMessage {
                GlassCard {
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        HStack(spacing: Spacing.unit * 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(HetzlyColors.statusError)
                            Text(errorMessage)
                                .bodySecondary()
                        }
                        if isAuthError {
                            Text("Update the account in Settings → Robot Accounts.")
                                .caption()
                        }
                    }
                }
            }

            if !servers.isEmpty {
                VStack(spacing: Spacing.unit * 2) {
                    ForEach(servers) { item in
                        NavigationLink(value: RobotServerRoute(accountID: item.accountID, serverNumber: item.server.serverNumber)) {
                            DedicatedServerRowView(server: item.server)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// A single Robot dedicated server's row: status, name, product/DC chips,
/// and its public IP in monospaced digits — mirrors `ServerRowView`'s
/// layout so the two feel like the same design language.
private struct DedicatedServerRowView: View {
    let server: RobotServer

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(resourceStatus(for: server))

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(server.serverName)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(server.product)
                        GlassChip(server.dc)
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                if let ip = server.serverIP {
                    Text(ip)
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }
        }
    }
}

/// Maps a Robot server's status/cancellation to the design system's coarse
/// `ResourceStatus`: cancelled reads as an error state, "in process" (an
/// order/action in flight) reads as transitioning, "ready" reads as
/// running — dedicated servers don't have an off state the way Cloud VMs do.
private func resourceStatus(for server: RobotServer) -> ResourceStatus {
    if server.cancelled { return .error }
    switch server.status {
    case .ready: return .running
    case .inProcess: return .transitioning
    default: return .unknown
    }
}

#Preview {
    let accountID = UUID()
    return NavigationStack {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: Spacing.unit * 6) {
                    DedicatedSectionView(
                        servers: [
                            DashboardViewModel.DedicatedServerItem(
                                accountID: accountID,
                                server: RobotServer(
                                    serverIP: "192.0.2.10", serverIPv6Net: nil,
                                    serverNumber: 12345, serverName: "ax42-1",
                                    product: "AX42", dc: "FSN1-DC14", traffic: "unlimited",
                                    status: .ready, cancelled: false, paidUntil: "2026-08-01",
                                    ip: nil, subnet: nil
                                )
                            ),
                            DashboardViewModel.DedicatedServerItem(
                                accountID: accountID,
                                server: RobotServer(
                                    serverIP: "192.0.2.11", serverIPv6Net: nil,
                                    serverNumber: 12346, serverName: "sx65-storage",
                                    product: "SX65", dc: "FSN1-DC10", traffic: "unlimited",
                                    status: .inProcess, cancelled: false, paidUntil: nil,
                                    ip: nil, subnet: nil
                                )
                            ),
                            DashboardViewModel.DedicatedServerItem(
                                accountID: accountID,
                                server: RobotServer(
                                    serverIP: "192.0.2.12", serverIPv6Net: nil,
                                    serverNumber: 12347, serverName: "ex44-old",
                                    product: "EX44", dc: "FSN1-DC8", traffic: "unlimited",
                                    status: .ready, cancelled: true, paidUntil: "2026-07-15",
                                    ip: nil, subnet: nil
                                )
                            ),
                        ],
                        errorMessage: nil
                    )

                    DedicatedSectionView(servers: [], errorMessage: "Couldn't reach Hetzner Robot right now. Check your connection and try again.")
                }
                .padding(Spacing.screenMargin)
            }
        }
    }
    .preferredColorScheme(.dark)
}

import HetznerKit
import SwiftUI

/// Failover IPs for one Robot account — pushed from `DedicatedView`'s
/// NETWORK section, mirroring `VSwitchListView`. Lists every failover IP
/// (monospaced address, currently routed-to server) — `DedicatedView` owns
/// the enclosing `NavigationStack` and registers
/// `.navigationDestination(for: FailoverRoute.self)`.
///
/// No auto-refresh timers, no background polling: loads once on first
/// appearance and on explicit pull-to-refresh only.
struct FailoverListView: View {
    let accountID: UUID

    @Environment(AppContainer.self) private var container
    @State private var viewModel = FailoverListViewModel()

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("Failover IPs")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(accountID: accountID, container: container)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if viewModel.failoverIPs.isEmpty {
                ResourceLoadingState()
            } else {
                list
            }
        case .failed(let message):
            if viewModel.failoverIPs.isEmpty {
                errorState(message)
            } else {
                list
            }
        case .loaded:
            if viewModel.failoverIPs.isEmpty {
                emptyState
            } else {
                list
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Failover IPs")
                Text("This Robot account has no failover IPs configured.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .alarm, scale: 3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.statusError)
            }
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            Button("Try Again") {
                Task { await viewModel.load(accountID: accountID, container: container) }
            }
            .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.unit * 3) {
                ForEach(viewModel.failoverIPs) { failover in
                    NavigationLink(value: FailoverRoute(accountID: accountID, ip: failover.ip)) {
                        FailoverRow(failover: failover)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.screenMargin)
        }
        .refreshable {
            await viewModel.load(accountID: accountID, container: container)
        }
    }
}

/// One failover IP's row: monospaced address and the server it's currently
/// routed to.
struct FailoverRow: View {
    let failover: RobotFailover

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(failover.ip)
                        .hetzlyMonoNumbers()
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text("Routed to \(failover.activeServerIP ?? "—")")
                        .bodySecondary()
                }

                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(spacing: Spacing.unit * 3) {
                    FailoverRow(failover: NetworkPreviewFixtures.failoverIP)
                }
                .padding(Spacing.screenMargin)
            }
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

import HetznerKit
import SwiftUI

/// vSwitches for one Robot account — pushed from `DedicatedView`'s NETWORK
/// section (`DedicatedView` owns the enclosing `NavigationStack` and
/// registers `.navigationDestination(for: VSwitchRoute.self)`, mirroring how
/// it already handles `RobotServerRoute`). Lists every vSwitch (name, VLAN,
/// server count, cancelled badge) and offers "New vSwitch" in the toolbar.
///
/// No auto-refresh timers, no background polling: loads once on first
/// appearance and on explicit pull-to-refresh only.
struct VSwitchListView: View {
    let accountID: UUID

    @Environment(AppContainer.self) private var container
    @State private var viewModel = VSwitchListViewModel()
    @State private var isPresentingCreate = false

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("vSwitches")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingCreate = true
                } label: {
                    Label("New vSwitch", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingCreate) {
            VSwitchCreateSheet(accountID: accountID) {
                await viewModel.load(accountID: accountID, container: container)
            }
        }
        .task {
            await viewModel.load(accountID: accountID, container: container)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if viewModel.vSwitches.isEmpty {
                ResourceLoadingState()
            } else {
                list
            }
        case .failed(let message):
            if viewModel.vSwitches.isEmpty {
                errorState(message)
            } else {
                list
            }
        case .loaded:
            if viewModel.vSwitches.isEmpty {
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
                Image(systemName: "square.split.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No vSwitches")
                Text("Create a vSwitch to bridge dedicated servers onto a private VLAN.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
            PrimaryCTA(title: "New vSwitch") { isPresentingCreate = true }
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
                ForEach(viewModel.vSwitches) { vSwitch in
                    NavigationLink(value: VSwitchRoute(accountID: accountID, vSwitchID: vSwitch.id)) {
                        VSwitchRow(vSwitch: vSwitch)
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

/// One vSwitch's row: name, monospaced VLAN chip, server count, cancelled
/// badge when applicable.
struct VSwitchRow: View {
    let vSwitch: RobotVSwitch

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(vSwitch.resourceStatus)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    HStack(spacing: Spacing.unit * 2) {
                        Text(vSwitch.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textPrimary)
                        if vSwitch.cancelled {
                            GlassChip("Cancelled")
                        }
                    }

                    HStack(spacing: Spacing.unit * 2) {
                        Text("VLAN \(vSwitch.vlan)")
                            .hetzlyMonoNumbers()
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textSecondary)
                        Text("· \(vSwitch.servers.count) server\(vSwitch.servers.count == 1 ? "" : "s")")
                            .bodySecondary()
                    }
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
                    VSwitchRow(vSwitch: NetworkPreviewFixtures.vSwitch)
                    VSwitchRow(vSwitch: NetworkPreviewFixtures.cancelledVSwitch)
                }
                .padding(Spacing.screenMargin)
            }
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

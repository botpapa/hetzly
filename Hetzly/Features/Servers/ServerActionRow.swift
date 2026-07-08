import HetznerKit
import SwiftUI

/// The row of circular glass power-action buttons, contextual to the
/// server's current status: `powerOn` only while off; `shutdown` / `reboot`
/// / `reset` / `powerOff` only while running. Mid-transition, no actions are
/// offered — the server is already busy.
///
/// Note: CONTRACTS.md's task text names only powerOn/shutdown/reboot/reset
/// for this row, but `PowerAction` also defines `powerOff` as a distinct
/// destructive hard-power-cut action (separate from `reset`'s hard reboot).
/// It's included here alongside the others while running so it has a home
/// in the UI — see worker report for this call.
struct ServerActionRow: View {
    let server: Server
    var onSelect: (PowerAction) -> Void

    @Namespace private var glassNamespace
    @State private var impactTrigger = false

    private var availableActions: [PowerAction] {
        switch server.status {
        case .off: [.powerOn]
        case .running: [.shutdown, .reboot, .reset, .powerOff]
        default: []
        }
    }

    var body: some View {
        Group {
            if availableActions.isEmpty {
                Text("\(server.status.displayName)…")
                    .caption()
                    .frame(height: 44)
            } else {
                GlassEffectContainer(spacing: 16) {
                    HStack(spacing: 16) {
                        ForEach(availableActions) { action in
                            actionButton(action)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: impactTrigger)
    }

    private func actionButton(_ action: PowerAction) -> some View {
        Button {
            impactTrigger.toggle()
            onSelect(action)
        } label: {
            Image(systemName: action.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(action.isDestructive ? HetzlyColors.destructive : HetzlyColors.textPrimary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(action.id, in: glassNamespace)
        .accessibilityLabel(action.title)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 8) {
            ServerActionRow(server: PreviewFixtures.server) { _ in }
            ServerActionRow(server: PreviewFixtures.offServer) { _ in }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

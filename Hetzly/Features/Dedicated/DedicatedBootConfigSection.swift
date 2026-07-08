import HetznerKit
import SwiftUI

/// Read-only BOOT CONFIGURATION rows: whether a Linux or VNC installation is
/// currently offered for this server (`GET /boot/{server-number}`). Purely
/// informational — Hetzly doesn't drive Linux/VNC install through this
/// screen, only surfaces availability.
///
/// NOTE (worker report flag): `RobotBootConfiguration`'s exact field names
/// weren't specified in CONTRACTS.md (only its method signature was). This
/// reads `.linux`/`.vnc` as optional properties whose mere presence
/// indicates availability, following Robot's real `/boot` response shape
/// (`rescue`/`linux`/`vnc`/`windows`/`plesk`/`cpanel`, each `null` or an
/// object) — reconcile against R1's actual model once the package lands.
struct DedicatedBootConfigSection: View {
    let bootConfiguration: RobotBootConfiguration?
    let state: DedicatedServerDetailViewModel.LoadState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            SectionLabel("Boot Configuration")

            GlassCard {
                switch state {
                case .idle, .loading:
                    HStack(spacing: Spacing.unit * 2) {
                        ProgressView()
                        Text("Loading boot configuration…").caption()
                    }
                case .failed(let message):
                    Text(message).caption()
                case .loaded:
                    VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                        availabilityRow(title: "Linux Installation", available: bootConfiguration?.linux != nil)
                        availabilityRow(title: "VNC Installation", available: bootConfiguration?.vnc != nil)
                    }
                }
            }
        }
    }

    private func availabilityRow(title: String, available: Bool) -> some View {
        HStack {
            Text(title).bodyPrimary()
            Spacer()
            Label(
                available ? "Available" : "Not Available",
                systemImage: available ? "checkmark.circle.fill" : "xmark.circle"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(available ? HetzlyColors.statusRunning : HetzlyColors.textTertiary)
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        DedicatedBootConfigSection(bootConfiguration: nil, state: .loaded)
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

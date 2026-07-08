import HetznerKit
import SwiftUI

/// PROTECTION row: a lock toggle for Hetzner's delete+rebuild protection
/// (flipped together, matching the Hetzner console's single switch). The
/// toggle never flips optimistically — it reflects the server's reported
/// state and hands the intent to the caller's confirm-then-track flow.
struct ServerProtectionRow: View {
    let server: Server
    var onToggle: (_ enable: Bool) -> Void

    private var isProtected: Bool { server.protection.delete }

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: isProtected ? "lock.shield.fill" : "lock.open")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isProtected ? HetzlyColors.statusRunning : HetzlyColors.textTertiary)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Deletion Protection")
                        .bodyPrimary()
                    Text(isProtected ? "Delete and rebuild are locked" : "Delete and rebuild are allowed")
                        .caption()
                }
                Spacer()
                Toggle("Deletion Protection", isOn: toggleBinding)
                    .labelsHidden()
                    .tint(HetzlyColors.accent)
            }
        }
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isProtected },
            set: { onToggle($0) }
        )
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ServerProtectionRow(server: PreviewFixtures.server) { _ in }
            .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

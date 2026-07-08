import HetznerKit
import SwiftUI

/// Multi-select server picker used to apply a firewall to servers. Servers
/// the firewall is already applied to are shown checked and disabled.
struct ApplyToServerSheet: View {
    let servers: [Server]
    let alreadyAppliedIDs: Set<Int>
    var onApply: ([Int]) -> Void
    var onCancel: () -> Void

    @State private var selectedIDs: Set<Int> = []

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                if servers.isEmpty {
                    VStack(spacing: Spacing.unit * 4) {
                        MascotView(state: .peek, scale: 3)
                        Text("No servers in this project to apply to.").bodySecondary()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: Spacing.unit * 2) {
                            ForEach(servers) { server in
                                serverRow(server)
                            }
                        }
                        .padding(Spacing.screenMargin)
                    }
                }
            }
            .navigationTitle("Apply to Servers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { onApply(Array(selectedIDs).sorted()) }
                        .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func serverRow(_ server: Server) -> some View {
        let isApplied = alreadyAppliedIDs.contains(server.id)
        let isSelected = isApplied || selectedIDs.contains(server.id)

        return Button {
            guard !isApplied else { return }
            withAnimation(.snappy) {
                if selectedIDs.contains(server.id) {
                    selectedIDs.remove(server.id)
                } else {
                    selectedIDs.insert(server.id)
                }
            }
        } label: {
            GlassCard(interactive: !isApplied) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? HetzlyColors.accent : HetzlyColors.textTertiary)

                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        Text(server.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textPrimary)
                        if let ipv4 = server.publicNet.ipv4?.ip {
                            Text(ipv4)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(HetzlyColors.textSecondary)
                        }
                    }

                    Spacer()

                    if isApplied {
                        GlassChip("Applied")
                    }
                }
            }
            .opacity(isApplied ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isApplied)
    }
}

#Preview {
    ApplyToServerSheet(
        servers: FirewallPreviewFixtures.servers,
        alreadyAppliedIDs: [42],
        onApply: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

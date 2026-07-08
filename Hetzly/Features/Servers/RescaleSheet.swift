import HetznerKit
import SwiftUI

/// Sheet for rescaling (change server type): lists server types of the same
/// architecture with their monthly price at this server's location, an
/// "upgrade disk" toggle (permanent!), and an honest description of the
/// chained steps when the server is running (shut down → resize → power on).
///
/// The caller (`ServerDetailView`) owns biometric gating and drives the
/// actual chain via `ServerDetailViewModel.runRescale`, which surfaces each
/// step in the active-action card.
struct RescaleSheet: View {
    let server: Server
    let serverTypes: [ServerType]
    let serverTypesState: ServerDetailViewModel.LoadState
    var onConfirm: (_ serverType: ServerType, _ upgradeDisk: Bool, _ powerOnAfter: Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: ServerType?
    @State private var upgradeDisk = false
    @State private var powerOnAfter = true

    private var isRunning: Bool { server.status == .running }

    /// Same-architecture, non-deprecated candidates, excluding the current
    /// type, sorted by core count then memory (roughly: by size).
    private var candidates: [ServerType] {
        serverTypes
            .filter { $0.architecture == server.serverType.architecture }
            .filter { $0.id != server.serverType.id }
            .filter { $0.deprecated != true }
            .sorted { ($0.cores, $0.memory) < ($1.cores, $1.memory) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            typeList

            optionRows

            stepsSummary

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                PrimaryCTA(title: "Resize") {
                    guard let selection else { return }
                    let upgrade = upgradeDisk
                    let powerOn = powerOnAfter
                    dismiss()
                    onConfirm(selection, upgrade, powerOn)
                }
                .frame(maxWidth: .infinity)
                .disabled(selection == nil)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .onChange(of: upgradeDisk) { _, upgrading in
            // Deselect a type that just became invalid for disk upgrade.
            guard upgrading, let current = selection, current.disk < server.primaryDiskSize else { return }
            withAnimation(.snappy) { selection = nil }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.unit * 3) {
            SheetHeaderBadge(systemImage: "arrow.up.left.and.arrow.down.right")
            VStack(alignment: .leading, spacing: 2) {
                Text("Rescale Server")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Text("\(server.name) · currently \(server.serverType.name)")
                    .caption()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var typeList: some View {
        switch serverTypesState {
        case .idle, .loading:
            VStack(spacing: Spacing.unit * 2) {
                Spacer()
                ProgressView()
                Text("Loading server types…").caption()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .failed(let message):
            VStack {
                Spacer()
                Text(message).bodySecondary().multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .loaded:
            ScrollView {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, type in
                            if index > 0 {
                                Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                            }
                            typeRow(type)
                        }
                    }
                }
            }
        }
    }

    private func typeRow(_ type: ServerType) -> some View {
        // Disk can never shrink: a type with a smaller nominal disk than the
        // current disk is only reachable by keeping the disk (no upgrade).
        let diskTooSmallToUpgrade = upgradeDisk && type.disk < server.primaryDiskSize
        return Button {
            withAnimation(.snappy) { selection = type }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selection?.id == type.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection?.id == type.id ? HetzlyColors.accent : HetzlyColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.name)
                        .bodyPrimary()
                    Text(specLine(type) + (diskTooSmallToUpgrade ? " · disk smaller than current — keep disk to select" : ""))
                        .caption()
                        .monospacedDigit()
                }
                Spacer()
                if let price = monthlyPrice(type) {
                    Text(price)
                        .hetzlyMonoNumbers()
                        .font(.system(size: 15, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(diskTooSmallToUpgrade)
        .opacity(diskTooSmallToUpgrade ? 0.4 : 1)
    }

    private var optionRows: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            Toggle(isOn: $upgradeDisk.animation(.snappy)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade disk to new type's size")
                        .bodyPrimary()
                    Text("Permanent — once the disk grows you can never rescale to a smaller-disk type again.")
                        .caption()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(HetzlyColors.accent)

            if isRunning {
                Toggle(isOn: $powerOnAfter) {
                    Text("Power back on when done")
                        .bodyPrimary()
                }
                .tint(HetzlyColors.accent)
            }
        }
    }

    private var stepsSummary: some View {
        Label(
            isRunning
                ? "The server is running, so Hetzly will: shut it down, wait until it's off, resize\(powerOnAfter ? ", then power it back on" : ", and leave it off"). Each step shows in the progress card."
                : "The server is off — Hetzly resizes it in place. Power it on afterwards from the action row.",
            systemImage: "list.number"
        )
        .caption()
        .fixedSize(horizontal: false, vertical: true)
    }

    private func specLine(_ type: ServerType) -> String {
        let ram = type.memory.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", type.memory)
            : String(format: "%.1f", type.memory)
        return "\(type.cores) vCPU · \(ram) GB RAM · \(type.disk) GB disk"
    }

    /// Net monthly price at this server's location, e.g. "€6.80/mo". Falls
    /// back to `nil` (row shows no price) when the type has no price entry
    /// for the location.
    private func monthlyPrice(_ type: ServerType) -> String? {
        let locationName = server.datacenter.location.name
        guard let entry = type.prices.first(where: { $0.location == locationName }),
              let net = entry.monthly.netDecimal else { return nil }
        let number = NSDecimalNumber(decimal: net)
        return String(format: "€%.2f/mo", number.doubleValue)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        RescaleSheet(
            server: PreviewFixtures.server,
            serverTypes: [PreviewFixtures.smallerServerType, PreviewFixtures.biggerServerType],
            serverTypesState: .loaded
        ) { _, _, _ in }
    }
}

import HetznerKit
import SwiftUI

/// The "Dedicated & Manual" section of the Costs tab: Robot dedicated
/// servers — auto-listed from every configured Robot account, each priced
/// manually — plus free-form manual fixed costs, in one coherent card.
///
/// Robot servers without a set price show a "Set price" row instead of an
/// amount; tapping any dedicated row (priced or not) opens
/// `DedicatedPriceSheet`. Manual entries below keep their existing
/// swipe-to-edit/delete behavior via the shared `SwipeRevealRow`.
struct DedicatedCostSection: View {
    let dedicatedServers: [CostsViewModel.DedicatedServerRow]
    let dedicatedErrorMessage: String?
    let manualEntries: [ManualCostEntry]
    let currency: String
    let onSetPrice: (CostsViewModel.DedicatedServerRow) -> Void
    let onAddManual: () -> Void
    let onEditManual: (ManualCostEntry) -> Void
    let onDeleteManual: (ManualCostEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Dedicated & Manual")
                Spacer()
                if total > 0 {
                    Text(total, format: .currency(code: currency))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    if let dedicatedErrorMessage {
                        HStack(spacing: Spacing.unit * 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(HetzlyColors.statusError)
                            Text(dedicatedErrorMessage)
                                .bodySecondary()
                        }
                    }

                    if dedicatedServers.isEmpty && manualEntries.isEmpty {
                        Text("Dedicated servers aren't visible to the Cloud API. Robot accounts list them automatically here — add a fixed monthly price for each so it counts toward your total.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if !dedicatedServers.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                            ForEach(dedicatedServers) { server in
                                dedicatedRow(server)
                            }
                        }
                    }

                    if !dedicatedServers.isEmpty && !manualEntries.isEmpty {
                        Divider().overlay(Color.white.opacity(0.08))
                    }

                    if !manualEntries.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                            ForEach(manualEntries) { entry in
                                SwipeRevealRow(
                                    onEdit: { onEditManual(entry) },
                                    onDelete: { onDeleteManual(entry) }
                                ) {
                                    manualRow(entry)
                                }
                            }
                        }
                    }

                    Button(action: onAddManual) {
                        Label("Add fixed cost", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(HetzlyColors.accent)
                    }
                    .buttonStyle(.plain)

                    if !dedicatedServers.isEmpty {
                        Text("Dedicated prices are entered manually — Robot has no pricing API for running servers.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var total: Decimal {
        let dedicatedTotal = dedicatedServers.compactMap(\.monthlyPrice).reduce(Decimal(0), +)
        let manualTotal = manualEntries.reduce(Decimal(0)) { $0 + $1.monthlyPrice }
        return dedicatedTotal + manualTotal
    }

    private func dedicatedRow(_ server: CostsViewModel.DedicatedServerRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
            StatusDot(resourceStatus(for: server))

            VStack(alignment: .leading, spacing: Spacing.unit) {
                Text(server.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .lineLimit(1)
                HStack(spacing: Spacing.unit * 2) {
                    GlassChip(server.product)
                    GlassChip(server.datacenter)
                }
            }

            Spacer(minLength: Spacing.unit * 2)

            if let price = server.monthlyPrice {
                Text("\(price, format: .currency(code: currency))/mo")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(HetzlyColors.textPrimary)
            } else {
                Text("Set price")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
            }
        }
        .padding(.vertical, Spacing.unit)
        .contentShape(Rectangle())
        .onTapGesture { onSetPrice(server) }
    }

    private func manualRow(_ entry: ManualCostEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .lineLimit(1)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .caption()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.unit * 2)

            Text("\(entry.monthlyPrice, format: .currency(code: currency))/mo")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(HetzlyColors.textPrimary)
        }
        .padding(.vertical, Spacing.unit)
        .contentShape(Rectangle())
    }
}

/// Maps a Robot server's status/cancellation into the design system's
/// coarse `ResourceStatus`: a cancelled server reads as an error state (it's
/// on its way out), "in process" (an order/action in flight) reads as
/// transitioning, and a plain "ready" server reads as running — dedicated
/// servers don't have an off state the way Cloud VMs do.
private func resourceStatus(for server: CostsViewModel.DedicatedServerRow) -> ResourceStatus {
    if server.cancelled { return .error }
    switch server.status {
    case .ready: return .running
    case .inProcess: return .transitioning
    default: return .unknown
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            VStack(spacing: Spacing.unit * 6) {
                DedicatedCostSection(
                    dedicatedServers: [
                        CostsViewModel.DedicatedServerRow(
                            accountID: UUID(), serverNumber: 12345, name: "ax42-1",
                            product: "AX42", datacenter: "FSN1-DC14", ip: "192.0.2.10",
                            status: .ready, cancelled: false,
                            monthlyPrice: Decimal(string: "39.00") ?? 0, note: nil
                        ),
                        CostsViewModel.DedicatedServerRow(
                            accountID: UUID(), serverNumber: 12346, name: "sx65-storage",
                            product: "SX65", datacenter: "FSN1-DC10", ip: "192.0.2.11",
                            status: .inProcess, cancelled: false,
                            monthlyPrice: nil, note: nil
                        ),
                    ],
                    dedicatedErrorMessage: nil,
                    manualEntries: [
                        ManualCostEntry(name: "Colocation rack", monthlyPrice: Decimal(string: "89.00") ?? 0, note: "Invoice R123456"),
                    ],
                    currency: "EUR",
                    onSetPrice: { _ in },
                    onAddManual: {},
                    onEditManual: { _ in },
                    onDeleteManual: { _ in }
                )

                DedicatedCostSection(
                    dedicatedServers: [],
                    dedicatedErrorMessage: "Couldn't reach Hetzner Robot right now. Check your connection and try again.",
                    manualEntries: [],
                    currency: "EUR",
                    onSetPrice: { _ in },
                    onAddManual: {},
                    onEditManual: { _ in },
                    onDeleteManual: { _ in }
                )
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}

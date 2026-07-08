import HetznerKit
import SwiftUI

/// Multi-select picker over the account's Robot servers not yet attached to
/// this vSwitch. Gathers a selection only — the caller
/// (`VSwitchDetailView`/`VSwitchDetailViewModel`) owns the actual
/// `addVSwitchServers` call, mirroring `EnableDedicatedRescueSheet`'s
/// gather-then-fire pattern.
struct VSwitchAddServerSheet: View {
    let availableServers: [RobotServer]
    let state: VSwitchDetailViewModel.LoadState
    var onAdd: ([Int]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            serverList

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                PrimaryCTA(title: "Add \(selected.count == 1 ? "Server" : "\(selected.count) Servers")") {
                    let numbers = Array(selected)
                    dismiss()
                    onAdd(numbers)
                }
                .frame(maxWidth: .infinity)
                .disabled(selected.isEmpty)
            }
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
            SheetHeaderBadge(systemImage: "plus.rectangle.on.folder")
            Text("Add Servers")
                .bodyPrimary()
                .fontWeight(.semibold)
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
            if availableServers.isEmpty {
                Text("Every dedicated server on this account is already attached to this vSwitch.")
                    .bodySecondary()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(availableServers.enumerated()), id: \.element.serverNumber) { index, server in
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
            withAnimation(.snappy) {
                if selected.contains(server.serverNumber) {
                    selected.remove(server.serverNumber)
                } else {
                    selected.insert(server.serverNumber)
                }
            }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selected.contains(server.serverNumber) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selected.contains(server.serverNumber) ? HetzlyColors.accent : HetzlyColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.displayName).bodyPrimary()
                    if let ip = server.serverIP {
                        Text(ip).hetzlyMonoNumbers().font(.system(size: 12, design: .monospaced)).foregroundStyle(HetzlyColors.textTertiary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        VSwitchAddServerSheet(
            availableServers: [DedicatedPreviewFixtures.server, DedicatedPreviewFixtures.inProcessServer],
            state: .loaded
        ) { _ in }
    }
}

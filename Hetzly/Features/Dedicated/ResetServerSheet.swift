import HetznerKit
import SwiftUI

/// Radio-style picker over the reset methods Robot actually reports as
/// available for this server (`resetOptions()`'s `type` array). Gathers a
/// selection only — the caller (`DedicatedServerDetailView`) owns biometric
/// gating for the destructive types (hw/man) and the actual `reset(type:)`
/// call, mirroring `EnableRescueSheet`/`RescaleSheet`'s gather-then-fire
/// pattern.
struct ResetServerSheet: View {
    let serverName: String
    let availableTypes: [RobotResetType]
    let resetInfoState: DedicatedServerDetailViewModel.LoadState
    var onSelect: (RobotResetType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: RobotResetType?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            typesList

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                Group {
                    if let selected, selected.isDestructive {
                        DestructiveCTA(title: "Reset") { confirm(selected) }
                    } else {
                        PrimaryCTA(title: "Reset") { if let selected { confirm(selected) } }
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(selected == nil)
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
            Image(systemName: "arrow.clockwise.circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HetzlyColors.accent)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Reset Server")
                    .bodyPrimary()
                    .fontWeight(.semibold)
                Text(serverName)
                    .caption()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var typesList: some View {
        switch resetInfoState {
        case .idle, .loading:
            HStack(spacing: Spacing.unit * 2) {
                ProgressView()
                Text("Loading reset options…").caption()
            }
        case .failed(let message):
            Text(message).caption()
        case .loaded:
            if availableTypes.isEmpty {
                Text("No reset methods are available for this server right now.")
                    .bodySecondary()
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                GlassCard {
                    VStack(spacing: 0) {
                        ForEach(Array(availableTypes.enumerated()), id: \.element) { index, type in
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

    private func typeRow(_ type: RobotResetType) -> some View {
        Button {
            withAnimation(.snappy) { selected = type }
        } label: {
            HStack(alignment: .top, spacing: Spacing.unit * 3) {
                Image(systemName: selected == type ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        selected == type
                            ? (type.isDestructive ? HetzlyColors.destructive : HetzlyColors.accent)
                            : HetzlyColors.textTertiary
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.title).bodyPrimary()
                    Text(type.plainExplanation)
                        .caption()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func confirm(_ type: RobotResetType) {
        dismiss()
        onSelect(type)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ResetServerSheet(
            serverName: "AX101 #12345",
            availableTypes: [.sw, .hw, .man],
            resetInfoState: .loaded
        ) { _ in }
    }
}

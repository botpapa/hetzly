import HetznerKit
import SwiftUI

/// Add-target sheet: pick a server, enter a label selector, or enter an IP.
struct LBTargetAddSheet: View {
    @Environment(AppContainer.self) private var container

    let servers: [Server]
    let existingTargets: [LBTarget]
    var onAdd: (LBTarget) -> Void
    var onCancel: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case server, labelSelector, ip
        var id: String { rawValue }

        var title: String {
            switch self {
            case .server: "Server"
            case .labelSelector: "Labels"
            case .ip: "IP"
            }
        }
    }

    @State private var kind: Kind = .server
    @State private var selectedServerID: Int?
    @State private var usePrivateIP = false
    @State private var selectorText = ""
    @State private var ipText = ""

    private var alreadyTargetedServerIDs: Set<Int> {
        Set(existingTargets.compactMap { $0.type == .server ? $0.server?.id : nil })
    }

    private var canAdd: Bool {
        switch kind {
        case .server:
            return selectedServerID != nil
        case .labelSelector:
            return !selectorText.trimmingCharacters(in: .whitespaces).isEmpty
        case .ip:
            return isPlausibleIP(ipText.trimmingCharacters(in: .whitespaces))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        InlineSegmentedPicker(
                            options: Kind.allCases,
                            selection: $kind,
                            label: \.title
                        )

                        switch kind {
                        case .server: serverPicker
                        case .labelSelector: selectorField
                        case .ip: ipField
                        }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("Add Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add).disabled(!canAdd)
                }
            }
        }
    }

    // MARK: - Server

    @ViewBuilder
    private var serverPicker: some View {
        if servers.isEmpty {
            VStack(spacing: Spacing.unit * 4) {
                if container.settings.mascotEnabled {
                    MascotView(state: .peek, scale: 3)
                } else {
                    Image(systemName: "tray")
                        .font(.system(size: 40))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
                Text("No servers in this project.").bodySecondary()
            }
            .frame(maxWidth: .infinity)
        } else {
            VStack(spacing: Spacing.unit * 2) {
                ForEach(servers) { server in
                    serverRow(server)
                }

                Toggle("Use private IP", isOn: $usePrivateIP)
                    .tint(HetzlyColors.accent)
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .padding(.top, Spacing.unit * 2)
            }
        }
    }

    private func serverRow(_ server: Server) -> some View {
        let isTargeted = alreadyTargetedServerIDs.contains(server.id)
        let isSelected = selectedServerID == server.id

        return Button {
            guard !isTargeted else { return }
            withAnimation(.snappy) { selectedServerID = server.id }
        } label: {
            GlassCard(interactive: !isTargeted) {
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
                    if isTargeted { GlassChip("Added") }
                }
            }
            .opacity(isTargeted ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isTargeted)
    }

    // MARK: - Label selector

    private var selectorField: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Label Selector")
            GlassCard {
                TextField("e.g. role=web", text: $selectorText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Text("Every server matching this selector becomes a target, now and in the future.")
                .caption()
        }
    }

    // MARK: - IP

    private var ipField: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("IP Address")
            GlassCard {
                TextField("e.g. 10.0.0.4", text: $ipText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.numbersAndPunctuation)
            }
            Text("Must be an IP routed in a network the load balancer is attached to.")
                .caption()
        }
    }

    /// Loose plausibility check (dotted-quad or contains-colon) — the API
    /// remains the source of truth for full validation.
    private func isPlausibleIP(_ text: String) -> Bool {
        if text.contains(":") {
            return text.count >= 2
        }
        let octets = text.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4 && octets.allSatisfy { Int($0).map { (0...255).contains($0) } == true }
    }

    private func add() {
        switch kind {
        case .server:
            guard let selectedServerID else { return }
            onAdd(LBTarget(
                type: .server,
                server: LBTargetServer(id: selectedServerID),
                labelSelector: nil,
                ip: nil,
                usePrivateIP: usePrivateIP,
                healthStatus: nil
            ))
        case .labelSelector:
            onAdd(LBTarget(
                type: .labelSelector,
                server: nil,
                labelSelector: LBTargetLabelSelector(selector: selectorText.trimmingCharacters(in: .whitespaces)),
                ip: nil,
                usePrivateIP: nil,
                healthStatus: nil
            ))
        case .ip:
            onAdd(LBTarget(
                type: .ip,
                server: nil,
                labelSelector: nil,
                ip: LBTargetIP(ip: ipText.trimmingCharacters(in: .whitespaces)),
                usePrivateIP: nil,
                healthStatus: nil
            ))
        }
    }
}

#Preview {
    LBTargetAddSheet(
        servers: FirewallPreviewFixtures.servers,
        existingTargets: LBPreviewFixtures.loadBalancer.targets,
        onAdd: { _ in },
        onCancel: {}
    )
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

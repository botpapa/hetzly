import HetznerKit
import SwiftUI

/// Unified snapshot of a primary or floating IP for the shared detail
/// screen. Built from either model; the closures the caller passes into
/// `IPDetailView` do the type-specific API work and return a fresh state.
struct IPDetailState: Sendable, Equatable {
    let name: String
    let ip: String
    let typeLabel: String
    let assignedServerID: Int?
    let dnsPtr: String?
    let protectionDelete: Bool
    /// `nil` for floating IPs (auto-delete is a primary-IP-only concept).
    let autoDelete: Bool?
    let locationLabel: String
    let created: Date
    let blocked: Bool

    init(primaryIP: PrimaryIP) {
        name = primaryIP.name
        ip = primaryIP.ip
        typeLabel = primaryIP.type == .ipv6 ? "IPv6" : "IPv4"
        assignedServerID = primaryIP.assigneeID
        dnsPtr = primaryIP.dnsPtr.first?.dnsPtr
        protectionDelete = primaryIP.protection.delete
        autoDelete = primaryIP.autoDelete
        locationLabel = "\(flagEmoji(countryCode: primaryIP.datacenter.location.country)) \(primaryIP.datacenter.location.city)"
        created = primaryIP.created
        blocked = primaryIP.blocked
    }

    init(floatingIP: FloatingIP) {
        name = floatingIP.name
        ip = floatingIP.ip
        typeLabel = floatingIP.type == .ipv6 ? "IPv6" : "IPv4"
        assignedServerID = floatingIP.server
        dnsPtr = floatingIP.dnsPtr.first?.dnsPtr
        protectionDelete = floatingIP.protection.delete
        autoDelete = nil
        locationLabel = "\(flagEmoji(countryCode: floatingIP.homeLocation.country)) \(floatingIP.homeLocation.city)"
        created = floatingIP.created
        blocked = floatingIP.blocked
    }
}

/// Shared detail screen for primary and floating IPs: assign/unassign via a
/// server picker, rDNS editing (nil resets to Hetzner's default), delete
/// protection, auto-delete (primary only), and delete in a danger zone.
///
/// Action-returning calls follow the ActionTracker-lite pattern: fire, show
/// a brief progress row, then swap in the fresh state the closure returns.
struct IPDetailView: View {
    let kindTitle: String
    let loadServers: () async throws -> [Server]
    let assign: (Int) async throws -> IPDetailState
    let unassign: () async throws -> IPDetailState
    let setRDNS: (String?) async throws -> IPDetailState
    let setProtection: (Bool) async throws -> IPDetailState
    let setAutoDelete: ((Bool) async throws -> IPDetailState)?
    let delete: () async throws -> Void
    var onChange: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var state: IPDetailState
    @State private var servers: [Server] = []
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var isPresentingRDNS = false
    @State private var isPresentingDeleteConfirm = false
    @State private var didDelete = false

    init(
        kindTitle: String,
        state: IPDetailState,
        loadServers: @escaping () async throws -> [Server],
        assign: @escaping (Int) async throws -> IPDetailState,
        unassign: @escaping () async throws -> IPDetailState,
        setRDNS: @escaping (String?) async throws -> IPDetailState,
        setProtection: @escaping (Bool) async throws -> IPDetailState,
        setAutoDelete: ((Bool) async throws -> IPDetailState)?,
        delete: @escaping () async throws -> Void,
        onChange: @escaping () -> Void = {}
    ) {
        self.kindTitle = kindTitle
        self.loadServers = loadServers
        self.assign = assign
        self.unassign = unassign
        self.setRDNS = setRDNS
        self.setProtection = setProtection
        self.setAutoDelete = setAutoDelete
        self.delete = delete
        self.onChange = onChange
        self._state = State(initialValue: state)
    }

    private var assignedServerName: String? {
        guard let serverID = state.assignedServerID else { return nil }
        return servers.first { $0.id == serverID }?.name ?? "Server #\(serverID)"
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                    summaryCard

                    if let actionError {
                        ResourceErrorBanner(message: actionError)
                    }

                    assignmentSection
                    rdnsSection
                    settingsSection
                    dangerZone
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationTitle(state.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            servers = (try? await loadServers()) ?? []
        }
        .sheet(isPresented: $isPresentingRDNS) {
            RDNSEditSheet(ip: state.ip, currentPTR: state.dnsPtr) { newPTR in
                performAction(reason: "Confirm changing reverse DNS for \(state.ip)") {
                    try await setRDNS(newPTR)
                }
            }
        }
        .confirmationDialog(
            "Delete \(kindTitle)",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(state.name)\".")
        }
        .onChange(of: didDelete) { _, deleted in
            guard deleted else { return }
            onChange()
            dismiss()
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                Text(state.ip)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .textSelection(.enabled)

                DetailInfoRow(label: "Type", value: state.typeLabel)
                DetailInfoRow(label: "Location", value: state.locationLabel)
                DetailInfoRow(label: "Created", value: ResourceFormatting.dateString(state.created))
                if state.blocked {
                    HStack(spacing: Spacing.unit * 2) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .foregroundStyle(HetzlyColors.statusError)
                        Text("This IP is blocked by Hetzner.").bodySecondary()
                    }
                }
                if isPerformingAction {
                    HStack(spacing: Spacing.unit * 2) {
                        ProgressView().tint(HetzlyColors.textSecondary)
                        Text("Working…").caption()
                    }
                }
            }
        }
    }

    // MARK: - Assignment

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Assignment")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    if let assignedServerName {
                        DetailInfoRow(label: "Assigned to", value: assignedServerName)
                        Button("Unassign", role: .destructive) {
                            performAction(reason: "Confirm unassigning \(state.ip)") {
                                try await unassign()
                            }
                        }
                        .secondaryCTAStyle()
                        .disabled(isPerformingAction)
                    } else {
                        Text("Not assigned to a server.").bodySecondary()
                        if servers.isEmpty {
                            Text("No servers in this project.").caption()
                        } else {
                            Menu {
                                ForEach(servers) { server in
                                    Button(server.name) {
                                        performAction(reason: "Confirm assigning \(state.ip) to \(server.name)") {
                                            try await assign(server.id)
                                        }
                                    }
                                }
                            } label: {
                                Text("Assign to Server…")
                            }
                            .secondaryCTAStyle()
                            .disabled(isPerformingAction)
                        }
                    }
                }
            }
        }
    }

    // MARK: - rDNS

    private var rdnsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Reverse DNS")
            GlassCard {
                HStack {
                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        Text(state.dnsPtr ?? "Hetzner default")
                            .hetzlyMonoNumbers()
                            .foregroundStyle(state.dnsPtr == nil ? HetzlyColors.textTertiary : HetzlyColors.textPrimary)
                        Text("PTR record for \(state.ip)").caption()
                    }
                    Spacer()
                    Button("Edit") { isPresentingRDNS = true }
                        .secondaryCTAStyle()
                        .disabled(isPerformingAction)
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Settings")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    Toggle(isOn: Binding(
                        get: { state.protectionDelete },
                        set: { enabled in
                            performAction(reason: "Confirm changing protection for \(state.ip)") {
                                try await setProtection(enabled)
                            }
                        }
                    )) {
                        Label("Delete protection", systemImage: "lock.shield")
                            .foregroundStyle(HetzlyColors.textPrimary)
                    }
                    .tint(HetzlyColors.accent)
                    .disabled(isPerformingAction)

                    if let setAutoDelete, let autoDelete = state.autoDelete {
                        Toggle(isOn: Binding(
                            get: { autoDelete },
                            set: { enabled in
                                performAction(reason: "Confirm changing auto-delete for \(state.ip)") {
                                    try await setAutoDelete(enabled)
                                }
                            }
                        )) {
                            Label("Auto-delete with server", systemImage: "arrow.3.trianglepath")
                                .foregroundStyle(HetzlyColors.textPrimary)
                        }
                        .tint(HetzlyColors.accent)
                        .disabled(isPerformingAction)
                    }
                }
            }
        }
    }

    // MARK: - Danger zone

    private var dangerZone: some View {
        DisclosureGroup {
            GlassCard {
                Button(role: .destructive) {
                    isPresentingDeleteConfirm = true
                } label: {
                    HStack {
                        Label("Delete \(kindTitle)", systemImage: "trash")
                            .foregroundStyle(state.protectionDelete ? HetzlyColors.textTertiary : HetzlyColors.destructive)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.unit * 2)
                }
                .buttonStyle(.plain)
                .disabled(state.protectionDelete || isPerformingAction)
            }
            .padding(.top, Spacing.unit * 3)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .tint(HetzlyColors.textTertiary)
    }

    // MARK: - Actions

    private func performAction(reason: String, _ action: @escaping () async throws -> IPDetailState) {
        guard !isPerformingAction else { return }
        actionError = nil
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                state = try await action()
                onChange()
            } catch {
                actionError = resourceUserMessage(for: error)
            }
        }
    }

    private func commitDelete() {
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting \(kindTitle.lowercased()) \"\(state.name)\""
            ) {
                try await delete()
            }
            if let error {
                actionError = error
            } else {
                didDelete = true
            }
        }
    }
}

/// Reverse-DNS edit sheet: a PTR hostname field, with an explicit "Reset to
/// default" that submits `nil` (Hetzner then restores its default PTR).
private struct RDNSEditSheet: View {
    let ip: String
    let currentPTR: String?
    let onSave: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ptr: String
    @State private var isSubmitting = false

    init(ip: String, currentPTR: String?, onSave: @escaping (String?) async -> Void) {
        self.ip = ip
        self.currentPTR = currentPTR
        self.onSave = onSave
        self._ptr = State(initialValue: currentPTR ?? "")
    }

    private var trimmedPTR: String {
        ptr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Reverse DNS").bodyPrimary().fontWeight(.semibold)
            Text(ip).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)

            GlassCard {
                TextField("ptr.example.com", text: $ptr)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .hetzlyMonoNumbers()
            }

            Button("Reset to Hetzner default") {
                submit(nil)
            }
            .secondaryCTAStyle()
            .disabled(isSubmitting)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Saving…" : "Save") {
                    submit(trimmedPTR.isEmpty ? nil : trimmedPTR)
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting || trimmedPTR.isEmpty)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private func submit(_ value: String?) {
        isSubmitting = true
        Task {
            await onSave(value)
            isSubmitting = false
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        IPDetailView(
            kindTitle: "Primary IP",
            state: IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[0]),
            loadServers: { ResourcesPreviewFixtures.servers },
            assign: { _ in IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[0]) },
            unassign: { IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[1]) },
            setRDNS: { _ in IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[0]) },
            setProtection: { _ in IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[0]) },
            setAutoDelete: { _ in IPDetailState(primaryIP: ResourcesPreviewFixtures.primaryIPs[0]) },
            delete: {}
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

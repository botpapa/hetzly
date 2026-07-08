import HetznerKit
import SwiftUI

/// Network detail: subnets and routes (add/delete each), attached servers
/// (detach), and delete in a collapsed danger zone.
struct NetworkDetailView: View {
    let network: Network
    var onChange: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss

    @State private var current: Network
    @State private var servers: [Server] = []
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var isPresentingAddSubnet = false
    @State private var isPresentingAddRoute = false
    @State private var isPresentingDeleteConfirm = false
    @State private var didDelete = false

    init(network: Network, onChange: @escaping () -> Void = {}) {
        self.network = network
        self.onChange = onChange
        self._current = State(initialValue: network)
    }

    private var client: CloudClient? {
        selection.projectID.flatMap { container.cloudClient(for: $0) }
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

                    subnetsSection
                    routesSection
                    serversSection
                    dangerZone
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadServers() }
        .sheet(isPresented: $isPresentingAddSubnet) {
            AddSubnetSheet { type, ipRange, zone in
                performAction(reason: "Confirm adding a subnet to \"\(current.name)\"") {
                    _ = try await client?.addSubnet(networkID: current.id, type: type, ipRange: ipRange, networkZone: zone)
                }
            }
        }
        .sheet(isPresented: $isPresentingAddRoute) {
            AddRouteSheet { destination, gateway in
                performAction(reason: "Confirm adding a route to \"\(current.name)\"") {
                    _ = try await client?.addRoute(networkID: current.id, destination: destination, gateway: gateway)
                }
            }
        }
        .confirmationDialog(
            "Delete Network",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(current.name)\".")
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
                DetailInfoRow(label: "IP Range", value: current.ipRange, monospaced: true)
                DetailInfoRow(label: "Created", value: ResourceFormatting.dateString(current.created))
                if isPerformingAction {
                    HStack(spacing: Spacing.unit * 2) {
                        ProgressView().tint(HetzlyColors.textSecondary)
                        Text("Working…").caption()
                    }
                }
            }
        }
    }

    // MARK: - Subnets

    private var subnetsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel("Subnets")
                Spacer()
                Button { isPresentingAddSubnet = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Add Subnet")
                    .disabled(isPerformingAction)
            }
            if current.subnets.isEmpty {
                GlassCard { Text("No subnets yet.").bodySecondary() }
            } else {
                ForEach(Array(current.subnets.enumerated()), id: \.offset) { _, subnet in
                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.unit) {
                                Text(subnet.ipRange ?? "—").hetzlyMonoNumbers()
                                Text("\(subnet.type.rawValue) · \(subnet.networkZone)").caption()
                            }
                            Spacer()
                            Button(role: .destructive) {
                                deleteSubnet(subnet)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete Subnet \(subnet.ipRange ?? "")")
                            .disabled(isPerformingAction || subnet.ipRange == nil)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Routes

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack {
                SectionLabel("Routes")
                Spacer()
                Button { isPresentingAddRoute = true } label: { Image(systemName: "plus.circle") }
                    .accessibilityLabel("Add Route")
                    .disabled(isPerformingAction)
            }
            if current.routes.isEmpty {
                GlassCard { Text("No custom routes.").bodySecondary() }
            } else {
                ForEach(Array(current.routes.enumerated()), id: \.offset) { _, route in
                    GlassCard {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.unit) {
                                Text(route.destination).hetzlyMonoNumbers()
                                Text("via \(route.gateway)").caption()
                            }
                            Spacer()
                            Button(role: .destructive) {
                                deleteRoute(route)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .accessibilityLabel("Delete Route \(route.destination)")
                            .disabled(isPerformingAction)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Attached servers

    private var serversSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Attached Servers")
            if current.servers.isEmpty {
                GlassCard { Text("No servers attached.").bodySecondary() }
            } else {
                ForEach(current.servers, id: \.self) { serverID in
                    GlassCard {
                        HStack {
                            Text(servers.first { $0.id == serverID }?.name ?? "Server #\(serverID)")
                                .bodyPrimary()
                            Spacer()
                            Button("Detach", role: .destructive) {
                                detachServer(serverID)
                            }
                            .secondaryCTAStyle()
                            .disabled(isPerformingAction)
                        }
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
                        Label("Delete Network", systemImage: "trash")
                            .foregroundStyle(current.protection.delete ? HetzlyColors.textTertiary : HetzlyColors.destructive)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.unit * 2)
                }
                .buttonStyle(.plain)
                .disabled(current.protection.delete || isPerformingAction)
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

    private func loadServers() async {
        guard let client else { return }
        servers = (try? await client.listServers()) ?? []
    }

    private func deleteSubnet(_ subnet: NetworkSubnet) {
        guard let ipRange = subnet.ipRange else { return }
        performAction(reason: "Confirm removing subnet \(ipRange)") {
            _ = try await client?.deleteSubnet(networkID: current.id, ipRange: ipRange)
        }
    }

    private func deleteRoute(_ route: NetworkRoute) {
        performAction(reason: "Confirm removing route \(route.destination)") {
            _ = try await client?.deleteRoute(networkID: current.id, destination: route.destination, gateway: route.gateway)
        }
    }

    private func detachServer(_ serverID: Int) {
        let name = servers.first { $0.id == serverID }?.name ?? "this server"
        performAction(reason: "Confirm detaching \(name) from \"\(current.name)\"") {
            _ = try await client?.detachServerFromNetwork(serverID: serverID, networkID: current.id)
        }
    }

    private func performAction(reason: String, _ action: @escaping () async throws -> Void) {
        guard !isPerformingAction, let client else { return }
        actionError = nil
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            do {
                try await action()
                if let refreshed = try? await client.network(id: current.id) {
                    current = refreshed
                }
                onChange()
            } catch {
                actionError = resourceUserMessage(for: error)
            }
        }
    }

    private func commitDelete() {
        guard let client else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting network \"\(current.name)\""
            ) {
                try await client.deleteNetwork(id: current.id)
            }
            if let error {
                actionError = error
            } else {
                didDelete = true
            }
        }
    }
}

// MARK: - Add subnet / route sheets

private struct AddSubnetSheet: View {
    let onAdd: (NetworkSubnetType, String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ipRange = ""
    @State private var networkZone = "eu-central"
    @State private var isSubmitting = false

    private var isValid: Bool {
        ResourceFormatting.isPlausibleIPv4CIDR(ipRange) && !networkZone.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Add Subnet").bodyPrimary().fontWeight(.semibold)

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    TextField("10.0.2.0/24", text: $ipRange)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .hetzlyMonoNumbers()
                    TextField("Network zone", text: $networkZone)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Adding…" : "Add") {
                    isSubmitting = true
                    Task {
                        await onAdd(.cloud, ipRange, networkZone)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(!isValid || isSubmitting)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

private struct AddRouteSheet: View {
    let onAdd: (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destination = ""
    @State private var gateway = ""
    @State private var isSubmitting = false

    private var isValid: Bool {
        ResourceFormatting.isPlausibleIPv4CIDR(destination) && !gateway.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Add Route").bodyPrimary().fontWeight(.semibold)

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    TextField("Destination, e.g. 0.0.0.0/0", text: $destination)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .hetzlyMonoNumbers()
                    TextField("Gateway, e.g. 10.0.1.1", text: $gateway)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .hetzlyMonoNumbers()
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Adding…" : "Add") {
                    isSubmitting = true
                    Task {
                        await onAdd(destination, gateway)
                        isSubmitting = false
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(!isValid || isSubmitting)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

#Preview {
    NavigationStack {
        NetworkDetailView(network: ResourcesPreviewFixtures.networks[0])
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}

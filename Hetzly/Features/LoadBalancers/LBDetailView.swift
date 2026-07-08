import HetznerKit
import SwiftUI

/// Load Balancer detail: hero glass card (IP, location, type, algorithm),
/// METRICS charts (reusing the Servers chart stack), SERVICES and TARGETS
/// sections with add/edit/remove, and a collapsed danger zone (change type,
/// attach/detach network, delete protection, delete).
struct LBDetailView: View {
    let projectID: UUID
    let loadBalancerID: Int
    var initialLoadBalancer: LoadBalancer?

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    /// Identifiable box for `.sheet(item:)` — `LBService` itself isn't
    /// `Identifiable`; its listen port is its identity on the wire.
    private struct EditingService: Identifiable {
        let service: LBService
        var id: Int { service.listenPort }
    }

    @State private var viewModel: LBDetailViewModel?
    @State private var isAlgorithmDialogPresented = false
    @State private var editingService: EditingService?
    @State private var isAddingService = false
    @State private var isAddingTarget = false
    @State private var pendingServiceDeletion: Int?
    @State private var pendingTargetRemoval: LBTarget?
    @State private var isTypeDialogPresented = false
    @State private var isNetworkDialogPresented = false
    @State private var isDeleteConfirmPresented = false

    init(projectID: UUID, loadBalancerID: Int, initialLoadBalancer: LoadBalancer? = nil) {
        self.projectID = projectID
        self.loadBalancerID = loadBalancerID
        self.initialLoadBalancer = initialLoadBalancer
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle(viewModel?.loadBalancer?.name ?? "Load Balancer")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = LBDetailViewModel(
                projectID: projectID,
                loadBalancerID: loadBalancerID,
                container: container,
                initial: initialLoadBalancer
            )
            viewModel = model
            async let detail: Void = model.load()
            async let metrics: Void = model.loadMetrics()
            _ = await (detail, metrics)
        }
        .onChange(of: viewModel?.didDelete) { _, deleted in
            guard deleted == true else { return }
            dismiss()
        }
        .sheet(isPresented: $isAddingService) {
            LBServiceEditSheet(
                existingService: nil,
                onSave: { service in
                    isAddingService = false
                    Task { await viewModel?.addService(service) }
                },
                onCancel: { isAddingService = false }
            )
        }
        .sheet(item: $editingService) { editing in
            LBServiceEditSheet(
                existingService: editing.service,
                onSave: { updated in
                    editingService = nil
                    Task { await viewModel?.updateService(updated) }
                },
                onCancel: { editingService = nil }
            )
        }
        .sheet(isPresented: $isAddingTarget) {
            LBTargetAddSheet(
                servers: viewModel?.servers ?? [],
                existingTargets: viewModel?.loadBalancer?.targets ?? [],
                onAdd: { target in
                    isAddingTarget = false
                    Task { await viewModel?.addTarget(target) }
                },
                onCancel: { isAddingTarget = false }
            )
        }
        .confirmationDialog(
            "Change Algorithm", isPresented: $isAlgorithmDialogPresented, titleVisibility: .visible
        ) {
            ForEach(LBAlgorithmType.editableCases, id: \.rawValue) { algorithm in
                Button(algorithm.displayName) {
                    Task { await viewModel?.changeAlgorithm(to: algorithm) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove Service",
            isPresented: Binding(
                get: { pendingServiceDeletion != nil },
                set: { if !$0 { pendingServiceDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Service", role: .destructive) {
                guard let listenPort = pendingServiceDeletion else { return }
                pendingServiceDeletion = nil
                Task { await viewModel?.deleteService(listenPort: listenPort) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Traffic on this port will no longer be forwarded.")
        }
        .confirmationDialog(
            "Remove Target",
            isPresented: Binding(
                get: { pendingTargetRemoval != nil },
                set: { if !$0 { pendingTargetRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Target", role: .destructive) {
                guard let target = pendingTargetRemoval else { return }
                pendingTargetRemoval = nil
                Task { await viewModel?.removeTarget(target) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The load balancer will stop sending traffic to this target.")
        }
        .confirmationDialog("Change Type", isPresented: $isTypeDialogPresented, titleVisibility: .visible) {
            ForEach(viewModel?.types ?? []) { type in
                if type.name != viewModel?.loadBalancer?.loadBalancerType.name {
                    Button(typeDialogLabel(type)) {
                        Task { await viewModel?.changeType(toTypeName: type.name) }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Network", isPresented: $isNetworkDialogPresented, titleVisibility: .visible) {
            networkDialogButtons
        }
        .confirmationDialog(
            "Delete Load Balancer", isPresented: $isDeleteConfirmPresented, titleVisibility: .visible
        ) {
            Button("Delete \"\(viewModel?.loadBalancer?.name ?? "")\"", role: .destructive) {
                confirmDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Traffic will stop being distributed to its targets. This cannot be undone.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.loadBalancer == nil { loadingState } else { loadedContent(viewModel) }
            case .failed(let message):
                if viewModel.loadBalancer == nil { errorState(message) } else { loadedContent(viewModel) }
            case .loaded:
                loadedContent(viewModel)
            }
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading load balancer…").caption()
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .alarm, scale: 3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.statusError)
            }
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            Button("Try Again") {
                Task { await viewModel?.load() }
            }
            .secondaryCTAStyle()
        }
    }

    @ViewBuilder
    private func loadedContent(_ viewModel: LBDetailViewModel) -> some View {
        if let loadBalancer = viewModel.loadBalancer {
            List {
                Group {
                    LBHeroCard(loadBalancer: loadBalancer) {
                        isAlgorithmDialogPresented = true
                    }

                    if let busyLabel = viewModel.busyLabel {
                        HStack(spacing: Spacing.unit * 2) {
                            ProgressView().controlSize(.small).tint(HetzlyColors.textSecondary)
                            Text(busyLabel).bodySecondary()
                            if container.settings.mascotEnabled {
                                Spacer()
                                MascotView(state: .work, scale: 1.5)
                            }
                        }
                    }

                    if let actionError = viewModel.actionError {
                        Text(actionError)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(HetzlyColors.destructive)
                    }

                    LBMetricsSection(
                        metrics: viewModel.metrics,
                        state: viewModel.metricsState,
                        range: Binding(
                            get: { viewModel.selectedRange },
                            set: { viewModel.selectedRange = $0 }
                        )
                    )
                    .padding(.vertical, Spacing.unit * 2)
                }
                .plainRow()

                servicesSection(loadBalancer, isBusy: viewModel.busyLabel != nil)
                targetsSection(loadBalancer, viewModel: viewModel)
                dangerZoneSection(loadBalancer, viewModel: viewModel)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable {
                async let detail: Void = viewModel.load()
                async let metrics: Void = viewModel.loadMetrics()
                _ = await (detail, metrics)
            }
        }
    }

    // MARK: - Services

    private func servicesSection(_ loadBalancer: LoadBalancer, isBusy: Bool) -> some View {
        Section {
            if loadBalancer.services.isEmpty {
                Text("No services yet — add one to start forwarding traffic.")
                    .caption()
                    .plainRow()
            } else {
                ForEach(Array(loadBalancer.services.enumerated()), id: \.element.listenPort) { _, service in
                    Button {
                        guard !isBusy else { return }
                        editingService = EditingService(service: service)
                    } label: {
                        LBServiceRow(service: service)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingServiceDeletion = service.listenPort
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                    .opacity(isBusy ? 0.55 : 1)
                }
            }

            Button {
                isAddingService = true
            } label: {
                Label("Add Service", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .plainRow()
        } header: {
            SectionLabel("Services")
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin))
        }
    }

    // MARK: - Targets

    private func targetsSection(_ loadBalancer: LoadBalancer, viewModel: LBDetailViewModel) -> some View {
        let isBusy = viewModel.busyLabel != nil
        return Section {
            if loadBalancer.targets.isEmpty {
                Text("No targets yet — traffic has nowhere to go.")
                    .caption()
                    .plainRow()
            } else {
                ForEach(Array(loadBalancer.targets.enumerated()), id: \.offset) { _, target in
                    LBTargetRow(target: target, servers: viewModel.servers)
                        .plainRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingTargetRemoval = target
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                        .opacity(isBusy ? 0.55 : 1)
                }
            }

            Button {
                isAddingTarget = true
            } label: {
                Label("Add Target", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .plainRow()
        } header: {
            SectionLabel("Targets")
                .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin))
        }
    }

    // MARK: - Danger zone

    private func dangerZoneSection(_ loadBalancer: LoadBalancer, viewModel: LBDetailViewModel) -> some View {
        Section {
            LBDangerZone(
                loadBalancer: loadBalancer,
                isBusy: viewModel.busyLabel != nil,
                onExpand: { Task { await viewModel.loadDangerZoneData() } },
                onChangeType: { isTypeDialogPresented = true },
                onNetwork: { isNetworkDialogPresented = true },
                onToggleProtection: { enabled in
                    Task { await viewModel.setDeleteProtection(enabled) }
                },
                onDelete: { isDeleteConfirmPresented = true }
            )
            .plainRow()
        }
    }

    private func typeDialogLabel(_ type: LoadBalancerType) -> String {
        if let price = LBTypePriceFormatter.monthly(for: type, locationName: viewModel?.loadBalancer?.location.name) {
            return "\(type.name) · \(price)"
        }
        return type.name
    }

    @ViewBuilder
    private var networkDialogButtons: some View {
        let attachedIDs = Set(viewModel?.loadBalancer?.privateNet.map(\.network) ?? [])
        ForEach(viewModel?.networks ?? []) { network in
            if attachedIDs.contains(network.id) {
                Button("Detach from \(network.name)", role: .destructive) {
                    Task { await viewModel?.detachFromNetwork(networkID: network.id) }
                }
            } else {
                Button("Attach to \(network.name)") {
                    Task { await viewModel?.attachToNetwork(networkID: network.id) }
                }
            }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func confirmDelete() {
        Task {
            if container.settings.requireBiometricsForDestructive {
                let approved = await container.biometricGate.authenticate(
                    reason: "Confirm deleting the load balancer \"\(viewModel?.loadBalancer?.name ?? "")\""
                )
                guard approved else { return }
            }
            await viewModel?.delete()
        }
    }
}

// MARK: - Hero card

/// Hero glass card: name, public IPv4 (monospaced), location, type, and a
/// tappable algorithm chip that opens the change-algorithm dialog.
private struct LBHeroCard: View {
    let loadBalancer: LoadBalancer
    var onAlgorithmTap: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 2) {
                    let health = LBHealthSummary(targets: loadBalancer.targets)
                    Circle().fill(health.color).frame(width: 8, height: 8)
                    Text(health.label).bodySecondary()
                    Spacer()
                }

                Text(loadBalancer.name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(HetzlyColors.textPrimary)

                if let ipv4 = loadBalancer.publicNet.ipv4?.ip {
                    Text(ipv4)
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textPrimary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(loadBalancer.loadBalancerType.name, systemImage: "scale.3d")
                        GlassChip(locationLabel, systemImage: "mappin.and.ellipse")
                        Button(action: onAlgorithmTap) {
                            GlassChip(
                                loadBalancer.algorithm.type.displayName,
                                systemImage: "arrow.triangle.branch"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var locationLabel: String {
        "\(CountryFlag.emoji(countryCode: loadBalancer.location.country)) \(loadBalancer.location.city)"
    }
}

// MARK: - Service row

/// One service row: protocol chip, listen → destination ports (monospaced),
/// and a health-check summary caption.
private struct LBServiceRow: View {
    let service: LBService

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack(spacing: Spacing.unit * 2) {
                    GlassChip(service.protocol.displayName)
                    Text(":\(String(service.listenPort)) → :\(String(service.destinationPort))")
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }

                HStack(spacing: Spacing.unit * 2) {
                    if let healthCheck = service.healthCheck {
                        Text(healthCheckLabel(healthCheck)).caption()
                    }
                    if service.http?.stickySessions == true {
                        Text("· sticky").caption()
                    }
                    if service.http?.redirectHTTP == true {
                        Text("· redirects HTTP").caption()
                    }
                }
            }
        }
    }

    private func healthCheckLabel(_ check: LBHealthCheck) -> String {
        var label = "Health: \(check.protocol.displayName) every \(check.interval)s"
        if let path = check.http?.path {
            label += " at \(path)"
        }
        return label
    }
}

// MARK: - Target row

/// One target row: resolved server name / selector / IP plus per-service
/// health badges.
private struct LBTargetRow: View {
    let target: LBTarget
    let servers: [Server]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack(spacing: Spacing.unit * 2) {
                    Image(systemName: target.systemImage)
                        .font(.system(size: 14))
                        .foregroundStyle(HetzlyColors.textSecondary)
                    Text(target.displayName(servers: servers))
                        .font(.system(size: 16, weight: .semibold, design: target.type == .server ? .default : .monospaced))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Spacer()
                }

                if let healthStatus = target.healthStatus, !healthStatus.isEmpty {
                    FlowLayout(spacing: Spacing.unit * 1.5) {
                        ForEach(healthStatus, id: \.listenPort) { entry in
                            HStack(spacing: Spacing.unit) {
                                Circle().fill(color(for: entry.status)).frame(width: 6, height: 6)
                                Text(":\(String(entry.listenPort))")
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(HetzlyColors.textSecondary)
                            }
                            .padding(.horizontal, Spacing.unit * 2)
                            .padding(.vertical, Spacing.unit)
                            .background(Capsule(style: .continuous).fill(Color.white.opacity(0.06)))
                        }
                    }
                }
            }
        }
    }

    private func color(for state: LBTargetHealthState) -> Color {
        switch state {
        case .healthy: HetzlyColors.statusRunning
        case .unhealthy: HetzlyColors.statusError
        case .unknown: HetzlyColors.statusOff
        }
    }
}

// MARK: - Danger zone

private struct LBDangerZone: View {
    let loadBalancer: LoadBalancer
    let isBusy: Bool
    var onExpand: () -> Void
    var onChangeType: () -> Void
    var onNetwork: () -> Void
    var onToggleProtection: (Bool) -> Void
    var onDelete: () -> Void

    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            GlassCard {
                VStack(spacing: 0) {
                    row(title: "Change Type", systemImage: "arrow.up.left.and.arrow.down.right", action: onChangeType)
                    divider
                    row(
                        title: loadBalancer.privateNet.isEmpty ? "Attach to Network" : "Manage Network",
                        systemImage: "network",
                        action: onNetwork
                    )
                    divider
                    protectionRow
                    divider
                    deleteRow
                }
            }
            .padding(.top, Spacing.unit * 3)
        } label: {
            Text("Danger Zone")
                .font(.system(size: 13, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(HetzlyColors.textTertiary)
        }
        .tint(HetzlyColors.textTertiary)
        .onChange(of: isExpanded) { _, expanded in
            if expanded { onExpand() }
        }
    }

    private var divider: some View {
        Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
    }

    private func row(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .bodyPrimary()
                    .foregroundStyle(HetzlyColors.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            .padding(.vertical, Spacing.unit * 2)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private var protectionRow: some View {
        Toggle(isOn: Binding(
            get: { loadBalancer.protection.delete },
            set: { onToggleProtection($0) }
        )) {
            Label("Delete Protection", systemImage: "lock.shield")
                .bodyPrimary()
                .foregroundStyle(HetzlyColors.textSecondary)
        }
        .tint(HetzlyColors.accent)
        .padding(.vertical, Spacing.unit * 2)
        .disabled(isBusy)
    }

    private var deleteRow: some View {
        Button(action: onDelete) {
            HStack {
                Label("Delete Load Balancer", systemImage: "trash")
                    .foregroundStyle(HetzlyColors.destructive)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.destructive.opacity(0.6))
            }
            .padding(.vertical, Spacing.unit * 2)
        }
        .buttonStyle(.plain)
        .disabled(isBusy || loadBalancer.protection.delete)
        .opacity(loadBalancer.protection.delete ? 0.5 : 1)
    }
}

#Preview {
    NavigationStack {
        LBDetailView(
            projectID: UUID(),
            loadBalancerID: LBPreviewFixtures.loadBalancer.id,
            initialLoadBalancer: LBPreviewFixtures.loadBalancer
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

import HetznerKit
import SwiftUI

/// Primary IPs for the selected project — the (usually server-attached)
/// public addresses servers are reachable at.
struct PrimaryIPsListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<PrimaryIP>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: PrimaryIP?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                emptyTitle: "No Primary IPs",
                emptyMessage: "Primary IPs are usually created alongside a server, but you can also reserve one standalone.",
                emptyCTA: "Create Primary IP",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { primaryIP in
                NavigationLink {
                    IPDetailView(
                        kindTitle: "Primary IP",
                        state: IPDetailState(primaryIP: primaryIP),
                        loadServers: { try await client()?.listServers() ?? [] },
                        assign: { serverID in
                            _ = try await client()?.assignPrimaryIP(id: primaryIP.id, assigneeID: serverID)
                            return try await reloadState(primaryIP.id)
                        },
                        unassign: {
                            _ = try await client()?.unassignPrimaryIP(id: primaryIP.id)
                            return try await reloadState(primaryIP.id)
                        },
                        setRDNS: { ptr in
                            _ = try await client()?.setPrimaryIPRDNS(id: primaryIP.id, ip: primaryIP.ip, dnsPtr: ptr)
                            return try await reloadState(primaryIP.id)
                        },
                        setProtection: { enabled in
                            _ = try await client()?.changePrimaryIPProtection(id: primaryIP.id, delete: enabled)
                            return try await reloadState(primaryIP.id)
                        },
                        setAutoDelete: { enabled in
                            _ = try await client()?.updatePrimaryIP(id: primaryIP.id, autoDelete: enabled)
                            return try await reloadState(primaryIP.id)
                        },
                        delete: { try await client()?.deletePrimaryIP(id: primaryIP.id) },
                        onChange: { Task { await model.refresh() } }
                    )
                } label: {
                    IPRow(name: primaryIP.name, ip: primaryIP.ip, assigned: primaryIP.assigneeID != nil)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = primaryIP
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Primary IPs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            IPCreateSheet(kind: .primary, projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Primary IP",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(pendingDelete?.name ?? "")\".")
        }
        .alert(
            "Something Went Wrong",
            isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private func client() -> CloudClient? {
        selection.projectID.flatMap { container.cloudClient(for: $0) }
    }

    private func reloadState(_ id: Int) async throws -> IPDetailState {
        guard let client = client() else { throw HetznerAPIError.transport(underlying: "No client") }
        return IPDetailState(primaryIP: try await client.primaryIP(id: id))
    }

    private func reload() async {
        guard let client = client() else {
            model = ResourceListModel(load: { [] })
            return
        }
        model = ResourceListModel(load: { try await client.listPrimaryIPs() })
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let primaryIP = pendingDelete, let client = client() else { return }
        pendingDelete = nil
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting primary IP \"\(primaryIP.name)\""
            ) {
                try await client.deletePrimaryIP(id: primaryIP.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

/// Shared row style for primary and floating IPs: name, monospaced address,
/// and an assigned/unassigned indicator.
struct IPRow: View {
    let name: String
    let ip: String
    let assigned: Bool

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "network")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)
                    Text(ip)
                        .hetzlyMonoNumbers()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }

                Spacer(minLength: Spacing.unit * 2)

                Image(systemName: assigned ? "server.rack" : "questionmark.circle")
                    .foregroundStyle(assigned ? HetzlyColors.statusRunning : HetzlyColors.textTertiary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.primaryIPs) { ip in
                    IPRow(name: ip.name, ip: ip.ip, assigned: ip.assigneeID != nil)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}

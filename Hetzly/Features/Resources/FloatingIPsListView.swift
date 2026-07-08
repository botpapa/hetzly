import HetznerKit
import SwiftUI

/// Floating IPs for the selected project — standalone addresses that can be
/// re-assigned between servers within the same location.
struct FloatingIPsListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<FloatingIP>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: FloatingIP?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                freshness: model.freshnessBanner,
                emptyTitle: "No Floating IPs",
                emptyMessage: "Floating IPs move with your traffic — reassign one to a new server for zero-downtime failover.",
                emptyCTA: "Create Floating IP",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { floatingIP in
                NavigationLink {
                    IPDetailView(
                        kindTitle: "Floating IP",
                        state: IPDetailState(floatingIP: floatingIP),
                        loadServers: { try await client()?.listServers() ?? [] },
                        assign: { serverID in
                            _ = try await client()?.assignFloatingIP(id: floatingIP.id, serverID: serverID)
                            return try await reloadState(floatingIP.id)
                        },
                        unassign: {
                            _ = try await client()?.unassignFloatingIP(id: floatingIP.id)
                            return try await reloadState(floatingIP.id)
                        },
                        setRDNS: { ptr in
                            _ = try await client()?.setFloatingIPRDNS(id: floatingIP.id, ip: floatingIP.ip, dnsPtr: ptr)
                            return try await reloadState(floatingIP.id)
                        },
                        setProtection: { enabled in
                            _ = try await client()?.changeFloatingIPProtection(id: floatingIP.id, delete: enabled)
                            return try await reloadState(floatingIP.id)
                        },
                        setAutoDelete: nil,
                        delete: { try await client()?.deleteFloatingIP(id: floatingIP.id) },
                        onChange: { Task { await model.refresh() } }
                    )
                } label: {
                    IPRow(name: floatingIP.name, ip: floatingIP.ip, assigned: floatingIP.server != nil)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = floatingIP
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Floating IPs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create Floating IP")
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            IPCreateSheet(kind: .floating, projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Floating IP",
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
        return IPDetailState(floatingIP: try await client.floatingIP(id: id))
    }

    private func reload() async {
        guard let projectID = selection.projectID, let client = client() else {
            model = ResourceListModel(load: { [] })
            return
        }
        model = ResourceListModel(load: { try await client.listFloatingIPs() }, cacheKey: "floatingIPs#\(projectID)")
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let floatingIP = pendingDelete, let client = client() else { return }
        pendingDelete = nil
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting floating IP \"\(floatingIP.name)\""
            ) {
                try await client.deleteFloatingIP(id: floatingIP.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.floatingIPs) { ip in
                    IPRow(name: ip.name, ip: ip.ip, assigned: ip.server != nil)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}

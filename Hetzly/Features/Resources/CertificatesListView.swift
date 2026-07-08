import HetznerKit
import SwiftUI

/// TLS certificates for the selected project — Hetzner-managed (Let's
/// Encrypt) or uploaded.
struct CertificatesListView: View {
    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection

    @State private var model = ResourceListModel<Certificate>(load: { [] })
    @State private var isPresentingCreate = false
    @State private var pendingDelete: Certificate?
    @State private var actionError: String?

    var body: some View {
        ZStack {
            CanvasBackground()
            resourceListBody(
                state: model.state,
                items: model.items,
                freshness: model.freshnessBanner,
                emptyTitle: "No Certificates",
                emptyMessage: "Request a managed Let's Encrypt certificate or upload your own for load balancers.",
                emptyCTA: "Create Certificate",
                onCreate: { isPresentingCreate = true },
                onRetry: { Task { await model.refresh() } },
                onRefresh: { await model.refresh() }
            ) { certificate in
                NavigationLink {
                    CertificateDetailView(certificate: certificate, onChange: { Task { await model.refresh() } })
                } label: {
                    CertificateRow(certificate: certificate)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = certificate
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle("Certificates")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isPresentingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Create Certificate")
            }
        }
        .task(id: selection.projectID) { await reload() }
        .sheet(isPresented: $isPresentingCreate) {
            CertificateCreateSheet(projectID: selection.projectID) {
                Task { await model.refresh() }
            }
        }
        .confirmationDialog(
            "Delete Certificate",
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

    private func reload() async {
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else {
            model = ResourceListModel(load: { [] })
            return
        }
        model = ResourceListModel(load: { try await client.listCertificates() }, cacheKey: "certificates#\(projectID)")
        await model.loadIfNeeded()
    }

    private func commitDelete() {
        guard let certificate = pendingDelete else { return }
        pendingDelete = nil
        guard let projectID = selection.projectID, let client = container.cloudClient(for: projectID) else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting certificate \"\(certificate.name)\""
            ) {
                try await client.deleteCertificate(id: certificate.id)
            }
            if let error {
                actionError = error
            } else {
                await model.refresh()
            }
        }
    }
}

struct CertificateRow: View {
    let certificate: Certificate

    private var status: ResourceStatus {
        guard certificate.type == .managed, let processStatus = certificate.status else {
            return .running
        }
        switch processStatus.issuance {
        case .completed: return .running
        case .pending: return .transitioning
        case .failed: return .error
        case .unknown: return .unknown
        }
    }

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                StatusDot(status)

                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Text(certificate.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(HetzlyColors.textPrimary)

                    HStack(spacing: Spacing.unit * 2) {
                        GlassChip(certificate.type == .managed ? "Managed" : "Uploaded")
                        Text(certificate.domainNames.first ?? "—")
                            .bodySecondary()
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Spacing.unit * 2)

                if certificate.domainNames.count > 1 {
                    GlassChip("+\(certificate.domainNames.count - 1)")
                }
            }
        }
    }
}

/// Certificate detail: domains, validity window, and (for managed certs)
/// issuance/renewal status.
struct CertificateDetailView: View {
    let certificate: Certificate
    var onChange: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss

    @State private var actionError: String?
    @State private var isPresentingDeleteConfirm = false

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

                    domainsSection

                    if certificate.type == .managed, let status = certificate.status {
                        managedStatusSection(status)
                    }

                    dangerZone
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationTitle(certificate.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete Certificate",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(certificate.name)\".")
        }
    }

    private var summaryCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                DetailInfoRow(label: "Type", value: certificate.type == .managed ? "Managed (Let's Encrypt)" : "Uploaded")
                if let notValidBefore = certificate.notValidBefore {
                    DetailInfoRow(label: "Valid from", value: ResourceFormatting.dateString(notValidBefore))
                }
                if let notValidAfter = certificate.notValidAfter {
                    DetailInfoRow(label: "Valid until", value: ResourceFormatting.dateString(notValidAfter))
                }
                if let fingerprint = certificate.fingerprint {
                    DetailInfoRow(
                        label: "Fingerprint",
                        value: ResourceFormatting.truncatedMiddle(fingerprint, keep: 11),
                        monospaced: true
                    )
                }
                DetailInfoRow(label: "Created", value: ResourceFormatting.dateString(certificate.created))
            }
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Domains")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                    ForEach(certificate.domainNames, id: \.self) { domain in
                        Text(domain)
                            .hetzlyMonoNumbers()
                            .foregroundStyle(HetzlyColors.textPrimary)
                    }
                }
            }
        }
    }

    private func managedStatusSection(_ status: CertificateStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Status")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    DetailInfoRow(label: "Issuance", value: processLabel(status.issuance))
                    DetailInfoRow(label: "Renewal", value: processLabel(status.renewal))
                }
            }
        }
    }

    private func processLabel(_ status: CertificateProcessStatus) -> String {
        switch status {
        case .pending: return "Pending"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .unknown: return "Unknown"
        }
    }

    private var dangerZone: some View {
        DisclosureGroup {
            GlassCard {
                Button(role: .destructive) {
                    isPresentingDeleteConfirm = true
                } label: {
                    HStack {
                        Label("Delete Certificate", systemImage: "trash")
                            .foregroundStyle(HetzlyColors.destructive)
                        Spacer()
                    }
                    .padding(.vertical, Spacing.unit * 2)
                }
                .buttonStyle(.plain)
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

    private func commitDelete() {
        guard let client else { return }
        Task {
            let error = await confirmDestructive(
                container: container,
                reason: "Confirm deleting certificate \"\(certificate.name)\""
            ) {
                try await client.deleteCertificate(id: certificate.id)
            }
            if let error {
                actionError = error
            } else {
                onChange()
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            VStack(spacing: Spacing.unit * 3) {
                ForEach(ResourcesPreviewFixtures.certificates) { certificate in
                    CertificateRow(certificate: certificate)
                }
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("Detail") {
    NavigationStack {
        CertificateDetailView(certificate: ResourcesPreviewFixtures.certificates[0])
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}

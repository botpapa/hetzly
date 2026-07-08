import HetznerKit
import SwiftUI

/// Volume detail: size/status/location, attach/detach, a grow-only resize
/// sheet, delete protection, and delete in a collapsed danger zone.
///
/// Action calls follow the "ActionTracker-lite" contract: fire the call,
/// show a brief in-row progress state, then reload — no polling to action
/// completion (unlike `ServerDetailViewModel`'s power actions).
struct VolumeDetailView: View {
    let volume: Volume
    var onChange: () -> Void = {}

    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection
    @Environment(\.dismiss) private var dismiss

    @State private var current: Volume
    @State private var servers: [Server] = []
    @State private var isPerformingAction = false
    @State private var actionError: String?
    @State private var isPresentingResize = false
    @State private var isPresentingDeleteConfirm = false
    @State private var didDelete = false

    init(volume: Volume, onChange: @escaping () -> Void = {}) {
        self.volume = volume
        self.onChange = onChange
        self._current = State(initialValue: volume)
    }

    private var client: CloudClient? {
        selection.projectID.flatMap { container.cloudClient(for: $0) }
    }

    private var attachedServer: Server? {
        guard let serverID = current.server else { return nil }
        return servers.first { $0.id == serverID }
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                    summaryCard
                    attachmentSection

                    if let actionError {
                        ResourceErrorBanner(message: actionError)
                    }

                    protectionSection
                    dangerZone
                }
                .padding(Spacing.screenMargin)
            }
        }
        .navigationTitle(current.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadServers() }
        .sheet(isPresented: $isPresentingResize) {
            VolumeResizeSheet(currentSizeGB: current.size) { newSize in
                performAction(reason: "Confirm resizing \"\(current.name)\"") {
                    _ = try await client?.resizeVolume(id: current.id, size: newSize)
                }
            }
        }
        .confirmationDialog(
            "Delete Volume",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { commitDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \"\(current.name)\" and all data on it.")
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
                HStack {
                    StatusDot(current.status == .available ? .running : .transitioning)
                    Text(current.status == .available ? "Available" : "Creating")
                        .bodySecondary()
                }
                DetailInfoRow(label: "Size", value: "\(current.size) GB")
                DetailInfoRow(label: "Location", value: "\(flagEmoji(countryCode: current.location.country)) \(current.location.city)")
                DetailInfoRow(label: "Format", value: current.format ?? "unformatted")
                DetailInfoRow(label: "Device", value: current.linuxDevice, monospaced: true)
                DetailInfoRow(label: "Created", value: ResourceFormatting.dateString(current.created))
            }
        }
    }

    // MARK: - Attachment

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Attachment")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    if let attachedServer {
                        DetailInfoRow(label: "Attached to", value: attachedServer.name)
                        Button("Detach", role: .destructive) {
                            performDetach()
                        }
                        .secondaryCTAStyle()
                        .disabled(isPerformingAction)
                    } else {
                        Text("Not attached to a server.").bodySecondary()
                        if servers.isEmpty {
                            Text("No servers in this project.").caption()
                        } else {
                            Menu {
                                ForEach(servers) { server in
                                    Button(server.name) { performAttach(serverID: server.id) }
                                }
                            } label: {
                                Text("Attach to Server…")
                            }
                            .secondaryCTAStyle()
                            .disabled(isPerformingAction)
                        }
                    }

                    Button("Resize…") { isPresentingResize = true }
                        .secondaryCTAStyle()
                        .disabled(isPerformingAction)

                    if isPerformingAction {
                        HStack(spacing: Spacing.unit * 2) {
                            ProgressView().tint(HetzlyColors.textSecondary)
                            Text("Working…").caption()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Protection

    private var protectionSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            SectionLabel("Protection")
            GlassCard {
                Toggle(isOn: Binding(
                    get: { current.protection.delete },
                    set: { toggleProtection($0) }
                )) {
                    Label("Delete protection", systemImage: "lock.shield")
                        .foregroundStyle(HetzlyColors.textPrimary)
                }
                .tint(HetzlyColors.accent)
                .disabled(isPerformingAction)
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
                        Label("Delete Volume", systemImage: "trash")
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

    private func performAttach(serverID: Int) {
        performAction(reason: "Confirm attaching \"\(current.name)\" to a server") {
            _ = try await client?.attachVolume(id: current.id, serverID: serverID, automount: true)
        }
    }

    private func performDetach() {
        performAction(reason: "Confirm detaching \"\(current.name)\"") {
            _ = try await client?.detachVolume(id: current.id)
        }
    }

    private func toggleProtection(_ enabled: Bool) {
        performAction(reason: "Confirm changing protection for \"\(current.name)\"") {
            _ = try await client?.changeVolumeProtection(id: current.id, delete: enabled)
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
                if let refreshed = try? await client.volume(id: current.id) {
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
                reason: "Confirm deleting volume \"\(current.name)\""
            ) {
                try await client.deleteVolume(id: current.id)
            }
            if let error {
                actionError = error
            } else {
                didDelete = true
            }
        }
    }
}

/// Grow-only resize sheet: Hetzner rejects shrinking a volume, so the
/// stepper's floor is the current size.
private struct VolumeResizeSheet: View {
    let currentSizeGB: Int
    let onResize: (Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var size: Double
    @State private var isSubmitting = false

    init(currentSizeGB: Int, onResize: @escaping (Int) async -> Void) {
        self.currentSizeGB = currentSizeGB
        self.onResize = onResize
        self._size = State(initialValue: Double(currentSizeGB))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Resize Volume").bodyPrimary().fontWeight(.semibold)
            Text("Volumes can only grow, never shrink.").caption()

            HStack {
                Text("New size").bodySecondary()
                Spacer()
                Text("\(Int(size)) GB").hetzlyMonoNumbers()
            }
            Slider(value: $size, in: Double(currentSizeGB)...10_240, step: 1)
                .tint(HetzlyColors.accent)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }.secondaryCTAStyle().frame(maxWidth: .infinity)
                PrimaryCTA(title: isSubmitting ? "Resizing…" : "Resize") {
                    isSubmitting = true
                    Task {
                        await onResize(Int(size))
                        isSubmitting = false
                        dismiss()
                    }
                }
                .frame(maxWidth: .infinity)
                .disabled(isSubmitting || Int(size) == currentSizeGB)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }
}

#Preview {
    NavigationStack {
        VolumeDetailView(volume: ResourcesPreviewFixtures.volumes[0])
            .environment(AppContainer.makeDefault())
            .environment(ResourcesProjectSelection())
    }
    .preferredColorScheme(.dark)
}

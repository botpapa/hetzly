import HetznerKit
import SwiftUI

/// Create-volume sheet: name, size (10–10240 GB), an optional location or
/// attach-to-server target (Hetzner requires exactly one of the two), and
/// filesystem format.
struct VolumeCreateSheet: View {
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var size: Double = 50
    @State private var format: VolumeFormat = .ext4
    @State private var attachesToServer = false
    @State private var selectedLocationID: Int?
    @State private var selectedServerID: Int?

    @State private var locations: [Location] = []
    @State private var servers: [Server] = []
    @State private var pricing: Pricing?

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private enum VolumeFormat: String, CaseIterable, Identifiable {
        case ext4, xfs
        var id: String { rawValue }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        guard !trimmedName.isEmpty, !isSubmitting else { return false }
        return attachesToServer ? selectedServerID != nil : selectedLocationID != nil
    }

    private var priceHint: String? {
        ResourceFormatting.volumeMonthlyPriceHint(sizeGB: Int(size), pricing: pricing)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        nameSection
                        sizeSection
                        targetSection
                        formatSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSubmitting ? "Creating…" : "Create Volume", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Volume")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
        .task { await loadReferenceData() }
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("e.g. data-01", text: $name)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            HStack {
                SectionLabel("Size")
                Spacer()
                Text("\(Int(size)) GB")
                    .hetzlyMonoNumbers()
                    .foregroundStyle(HetzlyColors.textPrimary)
            }
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit) {
                    Slider(value: $size, in: 10...10_240, step: 1)
                        .tint(HetzlyColors.accent)
                    if let priceHint {
                        Text(priceHint).caption()
                    }
                }
            }
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Location")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    Picker("Attach to", selection: $attachesToServer) {
                        Text("Standalone").tag(false)
                        Text("Attach to Server").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if attachesToServer {
                        Picker("Server", selection: $selectedServerID) {
                            Text("Choose a server").tag(Int?.none)
                            ForEach(servers) { server in
                                Text(server.name).tag(Optional(server.id))
                            }
                        }
                    } else {
                        Picker("Location", selection: $selectedLocationID) {
                            Text("Choose a location").tag(Int?.none)
                            ForEach(locations) { location in
                                Text("\(flagEmoji(countryCode: location.country)) \(location.city)").tag(Optional(location.id))
                            }
                        }
                    }
                }
            }
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Format")
            GlassCard {
                Picker("Format", selection: $format) {
                    ForEach(VolumeFormat.allCases) { candidate in
                        Text(candidate.rawValue).tag(candidate)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    // MARK: - Loading

    private func loadReferenceData() async {
        guard let projectID, let client = container.cloudClient(for: projectID) else { return }
        async let loadedLocations = try? client.listLocations()
        async let loadedServers = try? client.listServers()
        async let loadedPricing = try? client.pricing()
        locations = await loadedLocations ?? []
        servers = await loadedServers ?? []
        pricing = await loadedPricing
    }

    // MARK: - Submit

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName
        let size = Int(size)
        let format = format.rawValue
        let attachesToServer = attachesToServer
        let locationName = locations.first(where: { $0.id == selectedLocationID })?.name
        let serverID = selectedServerID

        Task {
            defer { isSubmitting = false }
            do {
                if attachesToServer {
                    _ = try await client.createVolume(name: name, size: size, serverID: serverID, automount: true, format: format)
                } else {
                    _ = try await client.createVolume(name: name, size: size, locationName: locationName, format: format)
                }
                onCreated()
                dismiss()
            } catch {
                errorMessage = resourceUserMessage(for: error)
            }
        }
    }
}

#Preview {
    VolumeCreateSheet(projectID: nil, onCreated: {})
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

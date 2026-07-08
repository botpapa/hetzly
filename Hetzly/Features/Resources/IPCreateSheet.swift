import HetznerKit
import SwiftUI

/// Which flavor of standalone IP this sheet creates. Both share the same
/// shape (name, address family, location, optional immediate assignee) —
/// only the underlying `CloudClient` call and location semantics differ
/// (datacenter for Primary IPs, home location for Floating IPs).
enum IPCreateKind {
    case primary
    case floating

    var title: String { self == .primary ? "New Primary IP" : "New Floating IP" }
    var ctaTitle: String { self == .primary ? "Create Primary IP" : "Create Floating IP" }
}

/// Create sheet shared by `PrimaryIPsListView` and `FloatingIPsListView`:
/// name, v4/v6 type, location, and an optional server to assign immediately.
struct IPCreateSheet: View {
    let kind: IPCreateKind
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: IPAddressType = .ipv4
    @State private var selectedLocationID: Int?
    @State private var selectedServerID: Int?

    @State private var locations: [Location] = []
    @State private var servers: [Server] = []

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && (selectedLocationID != nil || selectedServerID != nil) && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        nameSection
                        typeSection
                        locationSection
                        assigneeSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSubmitting ? "Creating…" : kind.ctaTitle, action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(kind.title)
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

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("e.g. spare-ip", text: $name)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Type")
            GlassCard {
                Picker("Type", selection: $type) {
                    Text("IPv4").tag(IPAddressType.ipv4)
                    Text("IPv6").tag(IPAddressType.ipv6)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel(kind == .primary ? "Datacenter" : "Home Location")
            GlassCard {
                Picker("Location", selection: $selectedLocationID) {
                    Text("Choose a location").tag(Int?.none)
                    ForEach(locations) { location in
                        Text("\(flagEmoji(countryCode: location.country)) \(location.city)").tag(Optional(location.id))
                    }
                }
            }
            Text("Ignored if you also pick a server below — the server's location is used instead.")
                .caption()
        }
    }

    private var assigneeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Assign To (Optional)")
            GlassCard {
                Picker("Server", selection: $selectedServerID) {
                    Text("None — create standalone").tag(Int?.none)
                    ForEach(servers) { server in
                        Text(server.name).tag(Optional(server.id))
                    }
                }
            }
        }
    }

    private func loadReferenceData() async {
        guard let projectID, let client = container.cloudClient(for: projectID) else { return }
        async let loadedLocations = try? client.listLocations()
        async let loadedServers = try? client.listServers()
        locations = await loadedLocations ?? []
        servers = await loadedServers ?? []
    }

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName
        let type = type
        let locationName = locations.first(where: { $0.id == selectedLocationID })?.name
        let serverID = selectedServerID
        let kind = kind

        Task {
            defer { isSubmitting = false }
            do {
                switch kind {
                case .primary:
                    _ = try await client.createPrimaryIP(name: name, type: type, datacenterName: serverID == nil ? locationName : nil, assigneeID: serverID)
                case .floating:
                    _ = try await client.createFloatingIP(name: name, type: type, homeLocationName: serverID == nil ? locationName : nil, serverID: serverID)
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
    IPCreateSheet(kind: .primary, projectID: nil, onCreated: {})
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

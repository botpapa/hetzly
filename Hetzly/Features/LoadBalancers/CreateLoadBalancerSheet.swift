import HetznerKit
import SwiftUI

/// Create-load-balancer sheet: name, location picker, type picker (with
/// monthly price), algorithm segmented control, and an optional private
/// network.
struct CreateLoadBalancerSheet: View {
    let projectID: UUID
    var onCreated: (LoadBalancer) -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var locations: [Location] = []
    @State private var types: [LoadBalancerType] = []
    @State private var networks: [Network] = []
    @State private var selectedLocationName: String?
    @State private var selectedTypeName: String?
    @State private var algorithm: LBAlgorithmType = .roundRobin
    @State private var selectedNetworkID: Int?
    @State private var isLoadingCatalog = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && selectedLocationName != nil && selectedTypeName != nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        nameSection

                        if isLoadingCatalog {
                            catalogPlaceholder
                        } else {
                            locationSection
                            typeSection
                            algorithmSection
                            networkSection
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSaving ? "Creating…" : "Create Load Balancer", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Load Balancer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .task { await loadCatalog() }
        }
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Sections

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("e.g. web-lb", text: $name)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var catalogPlaceholder: some View {
        VStack(spacing: Spacing.unit * 4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 56)
            }
        }
        .redacted(reason: .placeholder)
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Location")
            FlowLayout(spacing: Spacing.unit * 2) {
                ForEach(locations) { location in
                    selectableChip(
                        title: "\(CountryFlag.emoji(countryCode: location.country)) \(location.city)",
                        subtitle: location.name,
                        isSelected: selectedLocationName == location.name
                    ) {
                        withAnimation(.snappy) { selectedLocationName = location.name }
                    }
                }
            }
        }
    }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Type")
            VStack(spacing: Spacing.unit * 2) {
                ForEach(types) { type in
                    typeRow(type)
                }
            }
        }
    }

    private func typeRow(_ type: LoadBalancerType) -> some View {
        let isSelected = selectedTypeName == type.name
        return Button {
            withAnimation(.snappy) { selectedTypeName = type.name }
        } label: {
            GlassCard(interactive: true) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected ? HetzlyColors.accent : HetzlyColors.textTertiary)
                    VStack(alignment: .leading, spacing: Spacing.unit) {
                        Text(type.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textPrimary)
                        Text(limitsLabel(for: type)).caption()
                    }
                    Spacer()
                    if let price = LBTypePriceFormatter.monthly(for: type, locationName: selectedLocationName) {
                        Text(price)
                            .hetzlyMonoNumbers()
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(HetzlyColors.textSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func limitsLabel(for type: LoadBalancerType) -> String {
        var parts: [String] = []
        if let services = type.maxServices { parts.append("\(services) services") }
        if let targets = type.maxTargets { parts.append("\(targets) targets") }
        if let connections = type.maxConnections { parts.append("\(connections) conns") }
        return parts.joined(separator: " · ")
    }

    private var algorithmSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Algorithm")
            InlineSegmentedPicker(
                options: LBAlgorithmType.editableCases,
                selection: $algorithm,
                label: \.displayName
            )
        }
    }

    @ViewBuilder
    private var networkSection: some View {
        if !networks.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Private Network (Optional)")
                FlowLayout(spacing: Spacing.unit * 2) {
                    selectableChip(title: "None", subtitle: nil, isSelected: selectedNetworkID == nil) {
                        withAnimation(.snappy) { selectedNetworkID = nil }
                    }
                    ForEach(networks) { network in
                        selectableChip(
                            title: network.name,
                            subtitle: network.ipRange,
                            isSelected: selectedNetworkID == network.id
                        ) {
                            withAnimation(.snappy) { selectedNetworkID = network.id }
                        }
                    }
                }
            }
        }
    }

    private func selectableChip(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 2)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? HetzlyColors.accent.opacity(0.25) : Color.white.opacity(0.06))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(isSelected ? HetzlyColors.accent : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func loadCatalog() async {
        guard let client = container.cloudClient(for: projectID) else {
            errorMessage = "No stored credentials for this project."
            isLoadingCatalog = false
            return
        }
        async let locationsLoad = try? client.listLocations()
        async let typesLoad = try? client.listLoadBalancerTypes()
        async let networksLoad = try? client.listNetworks()
        locations = (await locationsLoad) ?? []
        types = (await typesLoad) ?? []
        networks = (await networksLoad) ?? []
        if selectedLocationName == nil { selectedLocationName = locations.first?.name }
        if selectedTypeName == nil { selectedTypeName = types.first?.name }
        isLoadingCatalog = false
        if locations.isEmpty || types.isEmpty {
            errorMessage = "Couldn't load locations and types. Pull to retry."
        }
    }

    private func submit() {
        guard canSubmit, let typeName = selectedTypeName else { return }
        errorMessage = nil
        isSaving = true
        let name = trimmedName
        let location = selectedLocationName
        let networkID = selectedNetworkID
        let algorithmType = algorithm

        Task {
            defer { isSaving = false }
            guard let client = container.cloudClient(for: projectID) else {
                errorMessage = "No stored credentials for this project."
                return
            }
            do {
                let created = try await client.createLoadBalancer(
                    name: name,
                    typeName: typeName,
                    algorithmType: algorithmType,
                    locationName: location,
                    networkID: networkID
                )
                onCreated(created.loadBalancer)
                dismiss()
            } catch let apiError as HetznerAPIError {
                errorMessage = apiError.userMessage
            } catch {
                errorMessage = "Something went wrong. Please try again."
            }
        }
    }
}

#Preview {
    CreateLoadBalancerSheet(projectID: UUID(), onCreated: { _ in })
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

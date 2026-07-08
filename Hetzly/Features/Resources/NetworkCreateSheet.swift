import HetznerKit
import SwiftUI

/// Create-network sheet: name, IP range (CIDR-validated), and an
/// auto-suggested first subnet (10.0.1.0/24 in the `eu-central` zone),
/// editable before submit.
struct NetworkCreateSheet: View {
    let projectID: UUID?
    let onCreated: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var ipRange = "10.0.0.0/16"
    @State private var subnetRange = "10.0.1.0/24"
    @State private var networkZone = "eu-central"

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isIPRangeValid: Bool {
        ResourceFormatting.isPlausibleIPv4CIDR(ipRange)
    }

    private var isSubnetRangeValid: Bool {
        subnetRange.isEmpty || ResourceFormatting.isPlausibleIPv4CIDR(subnetRange)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && isIPRangeValid && isSubnetRangeValid && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 7) {
                        nameSection
                        ipRangeSection
                        subnetSection

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(HetzlyColors.destructive)
                        }

                        PrimaryCTA(title: isSubmitting ? "Creating…" : "Create Network", action: submit)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSubmit)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle("New Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("Name")
            GlassCard {
                TextField("e.g. prod-net", text: $name)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
    }

    private var ipRangeSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("IP Range")
            GlassCard {
                TextField("10.0.0.0/16", text: $ipRange)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .hetzlyMonoNumbers()
            }
            if !isIPRangeValid {
                Text("Enter a valid IPv4 CIDR range, e.g. 10.0.0.0/16.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
        }
    }

    private var subnetSection: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
            SectionLabel("First Subnet")
            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    TextField("10.0.1.0/24", text: $subnetRange)
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
            if !isSubnetRangeValid {
                Text("Enter a valid IPv4 CIDR range, e.g. 10.0.1.0/24.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
            }
            Text("Leave the subnet blank to create the network without an initial subnet.")
                .caption()
        }
    }

    private func submit() {
        guard canSubmit, let projectID, let client = container.cloudClient(for: projectID) else { return }
        errorMessage = nil
        isSubmitting = true
        let name = trimmedName
        let ipRange = ipRange
        let subnets: [NetworkSubnetSpec] = subnetRange.isEmpty
            ? []
            : [NetworkSubnetSpec(type: .cloud, ipRange: subnetRange, networkZone: networkZone)]

        Task {
            defer { isSubmitting = false }
            do {
                _ = try await client.createNetwork(name: name, ipRange: ipRange, subnets: subnets)
                onCreated()
                dismiss()
            } catch {
                errorMessage = resourceUserMessage(for: error)
            }
        }
    }
}

#Preview {
    NetworkCreateSheet(projectID: nil, onCreated: {})
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

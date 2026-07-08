import HetznerKit
import SwiftUI

/// Sheet for creating a new vSwitch: a name field and a VLAN ID
/// stepper/field constrained to Robot's documented 4000–4091 range. Owns the
/// `createVSwitch` call itself (unlike the gather-then-fire sheets
/// elsewhere in Dedicated) since creation isn't a destructive action and
/// doesn't need caller-side biometric gating.
struct VSwitchCreateSheet: View {
    let accountID: UUID
    /// Called after a successful create so the list can reload.
    var onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppContainer.self) private var container

    @State private var name = ""
    @State private var vlanText = String(NetworkSupport.vlanRange.lowerBound)
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var vlan: Int? { Int(vlanText) }

    private var isValid: Bool {
        NetworkSupport.isValidVSwitchName(name) && vlan.map(NetworkSupport.isValidVLAN) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            header

            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Name")
                GlassCard {
                    TextField("e.g. Private Backend", text: $name)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
            }

            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("VLAN ID")
                GlassCard {
                    HStack {
                        TextField("4000–4091", text: $vlanText)
                            .textFieldStyle(.plain)
                            .keyboardType(.numberPad)
                            .hetzlyMonoNumbers()
                        Spacer()
                        Stepper(
                            "",
                            value: Binding(
                                get: { vlan ?? NetworkSupport.vlanRange.lowerBound },
                                set: { vlanText = String($0) }
                            ),
                            in: NetworkSupport.vlanRange
                        )
                        .labelsHidden()
                    }
                }
                Text("Robot vSwitch VLAN IDs range from \(NetworkSupport.vlanRange.lowerBound) to \(NetworkSupport.vlanRange.upperBound).")
                    .caption()
                if let vlan, !NetworkSupport.isValidVLAN(vlan) {
                    Text("Out of range.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(HetzlyColors.destructive)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(isSubmitting)

                PrimaryCTA(title: isSubmitting ? "Creating…" : "Create") { submit() }
                    .frame(maxWidth: .infinity)
                    .disabled(!isValid || isSubmitting)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private var header: some View {
        HStack(spacing: Spacing.unit * 3) {
            Image(systemName: "square.split.2x2")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(HetzlyColors.accent)
                .frame(width: 36, height: 36)
            Text("New vSwitch")
                .bodyPrimary()
                .fontWeight(.semibold)
            Spacer()
        }
    }

    private func submit() {
        guard let client = container.robotClient(for: accountID), let vlan else { return }
        isSubmitting = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                _ = try await client.createVSwitch(name: trimmedName, vlan: vlan)
                await onCreated()
                dismiss()
            } catch {
                errorMessage = VSwitchListViewModel.message(for: error)
            }
            isSubmitting = false
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        VSwitchCreateSheet(accountID: UUID()) {}
            .environment(AppContainer.makeDefault())
    }
}

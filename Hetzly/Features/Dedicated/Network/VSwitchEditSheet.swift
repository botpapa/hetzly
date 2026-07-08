import HetznerKit
import SwiftUI

/// Rename / change-VLAN sheet for an existing vSwitch. Owns the
/// `updateVSwitch` call itself (via the passed view model) — like
/// `VSwitchCreateSheet`, this isn't destructive and needs no biometric gate.
struct VSwitchEditSheet: View {
    let vSwitch: RobotVSwitch
    var viewModel: VSwitchDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var vlanText: String
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(vSwitch: RobotVSwitch, viewModel: VSwitchDetailViewModel) {
        self.vSwitch = vSwitch
        self.viewModel = viewModel
        self._name = State(initialValue: vSwitch.name)
        self._vlanText = State(initialValue: String(vSwitch.vlan))
    }

    private var vlan: Int? { Int(vlanText) }

    private var isValid: Bool {
        NetworkSupport.isValidVSwitchName(name) && vlan.map(NetworkSupport.isValidVLAN) == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            Text("Edit vSwitch").bodyPrimary().fontWeight(.semibold)

            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Name")
                GlassCard {
                    TextField("Name", text: $name)
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
                if let vlan, !NetworkSupport.isValidVLAN(vlan) {
                    Text("VLAN ID must be between \(NetworkSupport.vlanRange.lowerBound) and \(NetworkSupport.vlanRange.upperBound).")
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

                PrimaryCTA(title: isSubmitting ? "Saving…" : "Save") { submit() }
                    .frame(maxWidth: .infinity)
                    .disabled(!isValid || isSubmitting)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(420)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private func submit() {
        guard let vlan else { return }
        isSubmitting = true
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            let succeeded = await viewModel.update(name: trimmedName, vlan: vlan)
            isSubmitting = false
            if succeeded {
                dismiss()
            } else {
                errorMessage = viewModel.actionError
            }
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        VSwitchEditSheet(
            vSwitch: NetworkPreviewFixtures.vSwitch,
            viewModel: VSwitchDetailViewModel(
                route: VSwitchRoute(accountID: UUID(), vSwitchID: NetworkPreviewFixtures.vSwitch.id),
                container: AppContainer.makeDefault()
            )
        )
    }
}

import HetznerKit
import SwiftUI

/// Type-to-confirm sheet for zone deletion. Deleting a zone silently breaks
/// every domain it serves, so the delete button stays disarmed until the
/// user types the zone's exact name.
struct DeleteZoneConfirmSheet: View {
    let zone: DNSZone
    var isAuthenticating: Bool = false
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var typedName = ""
    @State private var warningTrigger = false
    @FocusState private var isFieldFocused: Bool

    private var isArmed: Bool {
        typedName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == zone.name.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "exclamationmark.triangle.fill", tint: HetzlyColors.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Delete Zone")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(zone.name)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(HetzlyColors.textTertiary)
                }
                Spacer()
            }

            Text(
                "Every DNS record in \(zone.name) is permanently deleted and the domain stops resolving. "
                    + "This cannot be undone."
            )
            .bodySecondary()
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                Text("Type \(zone.name) to confirm").caption()
                GlassCard {
                    TextField(zone.name, text: $typedName)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($isFieldFocused)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel", action: onCancel)
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
                    .disabled(isAuthenticating)

                DestructiveCTA(title: isAuthenticating ? "Verifying…" : "Delete Zone", action: onConfirm)
                    .frame(maxWidth: .infinity)
                    .disabled(!isArmed || isAuthenticating)
                    .opacity(isArmed ? 1 : 0.5)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .sensoryFeedback(.warning, trigger: warningTrigger)
        .onAppear {
            warningTrigger.toggle()
            isFieldFocused = true
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        DeleteZoneConfirmSheet(zone: DNSPreviewFixtures.zone, onConfirm: {}, onCancel: {})
    }
}

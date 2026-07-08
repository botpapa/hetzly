import SwiftUI

/// Sheet for creating a snapshot of the current server disk: an optional
/// description field and a primary CTA that hands off to the tracked
/// `createSnapshot` management action.
struct CreateSnapshotSheet: View {
    let serverName: String
    var onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var descriptionText = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "camera")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Create Snapshot")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(serverName)
                        .caption()
                }
                Spacer()
            }

            TextField("Description (optional)", text: $descriptionText)
                .bodyPrimary()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .padding(Spacing.unit * 3)
                .background {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                }

            Text("Snapshots capture the whole disk and are billed per GB of image size until you delete them. The server keeps running while the snapshot is taken.")
                .caption()
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                PrimaryCTA(title: "Create Snapshot") {
                    let description = descriptionText
                    dismiss()
                    onCreate(description)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .onAppear { fieldFocused = true }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        CreateSnapshotSheet(serverName: "hetzi-prod-01") { _ in }
    }
}

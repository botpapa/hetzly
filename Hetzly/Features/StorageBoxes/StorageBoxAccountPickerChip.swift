import SwiftUI

/// A `GlassChip` showing the currently-selected Storage Box account's label
/// plus a chevron; tapping opens a `Menu` listing every account so the user
/// can switch. Local to `StorageBoxes/` per the module contract — mirrors
/// `RobotAccountPickerChip` in `Dedicated/` exactly.
struct StorageBoxAccountPickerChip: View {
    let accounts: [StorageBoxAccountRecord]
    @Binding var selection: UUID?

    private var selectedLabel: String {
        guard let selection, let account = accounts.first(where: { $0.id == selection }) else {
            return "Select Account"
        }
        return account.label
    }

    var body: some View {
        Menu {
            ForEach(accounts) { account in
                Button {
                    selection = account.id
                } label: {
                    if account.id == selection {
                        Label(account.label, systemImage: "checkmark")
                    } else {
                        Text(account.label)
                    }
                }
            }
        } label: {
            GlassChip(selectedLabel, systemImage: "chevron.up.chevron.down")
        }
        .disabled(accounts.isEmpty)
    }
}

#Preview {
    @Previewable @State var selection: UUID? = UUID()

    return ZStack {
        CanvasBackground()
        StorageBoxAccountPickerChip(
            accounts: [
                StorageBoxAccountRecord(id: selection ?? UUID(), label: "Backups"),
                StorageBoxAccountRecord(label: "Archive"),
            ],
            selection: $selection
        )
    }
    .preferredColorScheme(.dark)
}

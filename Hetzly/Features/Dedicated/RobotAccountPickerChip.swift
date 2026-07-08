import SwiftUI

/// A `GlassChip` showing the currently-selected Robot account's label plus a
/// chevron; tapping opens a `Menu` listing every account so the user can
/// switch. Local to `Dedicated/` per the module contract — only `DedicatedView`
/// needs an account picker (`ProjectFilterBar` in `Dashboard/` is the
/// project-scoped equivalent for the Cloud side — Dashboard/Costs/Resources
/// all use it; Robot accounts aren't Cloud projects, so Dedicated keeps its
/// own small chip here rather than reusing that component).
struct RobotAccountPickerChip: View {
    let accounts: [RobotAccountRecord]
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
        RobotAccountPickerChip(
            accounts: [
                RobotAccountRecord(id: selection ?? UUID(), label: "Dedicated", username: "#ws+hetzly"),
                RobotAccountRecord(label: "Backup Account", username: "#ws+backup"),
            ],
            selection: $selection
        )
    }
    .preferredColorScheme(.dark)
}

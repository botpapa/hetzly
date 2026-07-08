import SwiftUI

/// A `GlassChip` showing the currently-selected project's name plus a
/// chevron; tapping opens a `Menu` listing every project so the user can
/// switch. Reused by Costs (Worker B) per the module contract — this is the
/// one place `ResourcesProjectSelection` gets a picker UI.
struct ProjectPickerChip: View {
    let projects: [ProjectRecord]
    @Binding var selection: UUID?

    private var selectedName: String {
        guard let selection, let project = projects.first(where: { $0.id == selection }) else {
            return "Select Project"
        }
        return project.name
    }

    var body: some View {
        Menu {
            ForEach(projects) { project in
                Button {
                    selection = project.id
                } label: {
                    if project.id == selection {
                        Label(project.name, systemImage: "checkmark")
                    } else {
                        Text(project.name)
                    }
                }
            }
        } label: {
            GlassChip(selectedName, systemImage: "chevron.up.chevron.down")
        }
        .disabled(projects.isEmpty)
    }
}

#Preview {
    @Previewable @State var selection: UUID? = UUID()

    return ZStack {
        CanvasBackground()
        ProjectPickerChip(
            projects: [
                ProjectRecord(id: selection ?? UUID(), name: "Personal", sortOrder: 0),
                ProjectRecord(name: "Work", sortOrder: 1),
            ],
            selection: $selection
        )
    }
    .preferredColorScheme(.dark)
}

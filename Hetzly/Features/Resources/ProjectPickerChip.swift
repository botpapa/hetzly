import SwiftUI

/// A `GlassChip` showing the currently-selected project's name plus a
/// chevron. Reused by Costs (Worker B) per the module contract — this is the
/// one place `ResourcesProjectSelection` gets a picker UI.
///
/// With a handful of projects, tapping opens a `Menu` (fast, no extra
/// screen). Menus can't host a search field, so once there are more than 6
/// projects — where scanning a menu stops being quick — tapping instead
/// presents a searchable sheet (`ProjectPickerSheet`) with the same
/// checkmark-on-current affordance.
struct ProjectPickerChip: View {
    let projects: [ProjectRecord]
    @Binding var selection: UUID?

    @State private var isPresentingPickerSheet = false

    /// Above this count a `Menu` stops being a fast way to find a project —
    /// a searchable sheet takes over instead.
    private static let menuThreshold = 6

    private var selectedName: String {
        guard let selection, let project = projects.first(where: { $0.id == selection }) else {
            return "Select Project"
        }
        return project.name
    }

    var body: some View {
        Group {
            if projects.count > Self.menuThreshold {
                Button {
                    isPresentingPickerSheet = true
                } label: {
                    GlassChip(selectedName, systemImage: "chevron.up.chevron.down")
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $isPresentingPickerSheet) {
                    ProjectPickerSheet(projects: projects, selection: $selection)
                }
            } else {
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
            }
        }
        .disabled(projects.isEmpty)
    }
}

/// Searchable list of every project, presented as a sheet when
/// `ProjectPickerChip` has too many projects for a `Menu` to stay usable.
/// Names only — no server counts, since showing them would mean an extra
/// network round-trip per project just to populate a picker.
private struct ProjectPickerSheet: View {
    let projects: [ProjectRecord]
    @Binding var selection: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredProjects: [ProjectRecord] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                if filteredProjects.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    List {
                        ForEach(filteredProjects) { project in
                            Button {
                                selection = project.id
                                dismiss()
                            } label: {
                                HStack {
                                    Text(project.name)
                                        .bodyPrimary()
                                    Spacer()
                                    if project.id == selection {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(HetzlyColors.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Select Project")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search projects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Menu (few projects)") {
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

#Preview("Sheet (many projects)") {
    @Previewable @State var selection: UUID? = UUID()
    let manyProjects = (0..<12).map { index in
        ProjectRecord(id: index == 0 ? (selection ?? UUID()) : UUID(), name: "Project \(index + 1)", sortOrder: index)
    }

    return ZStack {
        CanvasBackground()
        ProjectPickerChip(projects: manyProjects, selection: $selection)
    }
    .preferredColorScheme(.dark)
}

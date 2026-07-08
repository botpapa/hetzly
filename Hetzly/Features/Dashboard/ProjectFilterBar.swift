import SwiftUI

/// Horizontal project scope selector shown under the Dashboard's nav title,
/// above the burn card: an "All" chip, one chip per project, and a trailing
/// "+" chip that starts the add-project flow. Selecting a chip scopes the
/// entire dashboard (burn card, sections, attention list) to that project;
/// `nil` means "All".
///
/// Binding public API per the multi-project wave contract (`CONTRACTS.md`) —
/// reused as-is by any other feature that wants the same scope picker.
///
/// With more than 6 projects, the per-project chips collapse into a single
/// menu chip (current selection name + chevron, `Menu` listing every project
/// plus "All") so the bar never turns into an endless horizontal scroll.
struct ProjectFilterBar: View {
    let projects: [ProjectRecord]
    @Binding var selection: UUID?
    let onAddProject: () -> Void

    /// Above this many projects, per-project chips collapse into one menu
    /// chip per the contract ("the bar never becomes an endless scroll").
    private static let collapseThreshold = 6

    private var currentSelectionName: String {
        guard let selection, let project = projects.first(where: { $0.id == selection }) else {
            return "All"
        }
        return project.name
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.unit * 2) {
                FilterChip(title: "All", isSelected: selection == nil) {
                    select(nil)
                }

                if projects.count > Self.collapseThreshold {
                    projectMenuChip
                } else {
                    ForEach(projects) { project in
                        FilterChip(title: project.name, isSelected: selection == project.id) {
                            select(project.id)
                        }
                    }
                }

                addChip
            }
        }
        .scrollClipDisabled()
    }

    private var projectMenuChip: some View {
        Menu {
            Button("All") { select(nil) }
            if !projects.isEmpty {
                Divider()
                ForEach(projects) { project in
                    Button(project.name) { select(project.id) }
                }
            }
        } label: {
            HStack(spacing: Spacing.unit) {
                Text(currentSelectionName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .modifier(ChipStyle(isSelected: selection != nil))
        .accessibilityLabel("Project filter, currently \(currentSelectionName)")
    }

    private var addChip: some View {
        Button(action: onAddProject) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
        }
        .modifier(ChipStyle(isSelected: false))
        .accessibilityLabel("Add project")
    }

    private func select(_ projectID: UUID?) {
        withAnimation(.snappy) {
            selection = projectID
        }
    }
}

/// A single tappable "All"/project chip.
private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
        }
        .modifier(ChipStyle(isSelected: isSelected))
    }
}

/// Shared capsule chip chrome: label styling, sizing, and the Liquid Glass
/// background — accent-tinted + interactive when selected, plain interactive
/// glass otherwise. Solid fallback when
/// `accessibilityReduceTransparency` is on, matching `GlassChip`'s pattern.
private struct ChipStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let isSelected: Bool

    private var capsule: Capsule { Capsule(style: .continuous) }

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HetzlyColors.textPrimary)
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 1.5)
            .background {
                if reduceTransparency {
                    capsule
                        .fill(isSelected ? HetzlyColors.accent.opacity(0.35) : HetzlyColors.glassFallbackFill)
                        .overlay {
                            capsule.strokeBorder(isSelected ? HetzlyColors.accent : HetzlyColors.glassFallbackStroke, lineWidth: 1)
                        }
                } else {
                    Color.clear
                }
            }
            .modifier(ChipGlassEffect(shape: capsule, isSelected: isSelected, isEnabled: !reduceTransparency))
            .buttonStyle(.plain)
            .animation(.snappy, value: isSelected)
    }
}

private struct ChipGlassEffect: ViewModifier {
    let shape: Capsule
    let isSelected: Bool
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            if isSelected {
                content.glassEffect(Glass.regular.tint(HetzlyColors.accent).interactive(), in: shape)
            } else {
                content.glassEffect(.regular.interactive(), in: shape)
            }
        } else {
            content
        }
    }
}

#Preview("Few projects") {
    @Previewable @State var selection: UUID? = nil
    let projects = [
        ProjectRecord(name: "Production", sortOrder: 0),
        ProjectRecord(name: "Staging", sortOrder: 1),
        ProjectRecord(name: "Sandbox", sortOrder: 2),
    ]
    return ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 6) {
            ProjectFilterBar(projects: projects, selection: $selection, onAddProject: {})
            ProjectFilterBar(projects: projects, selection: .constant(projects[1].id), onAddProject: {})
        }
        .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

#Preview("Many projects (menu chip)") {
    @Previewable @State var selection: UUID? = nil
    let projects = (1...9).map { ProjectRecord(name: "Project \($0)", sortOrder: $0) }
    return ZStack {
        CanvasBackground()
        ProjectFilterBar(projects: projects, selection: $selection, onAddProject: {})
            .padding(.horizontal, Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

import HetznerKit
import SwiftUI

/// Sheet listing rebuild sources: system images grouped by OS flavor, plus
/// this server's own snapshots. Picking one dismisses and hands the image
/// back to `ServerDetailView`, which routes it through the standard
/// destructive confirm sheet + biometric gate before firing the tracked
/// `rebuild` action ("destroys all data on the disk").
struct RebuildSheet: View {
    let server: Server
    let images: [HetznerKit.Image]
    let imagesState: ServerDetailViewModel.LoadState
    /// Preselected image (snapshot-row shortcut) — highlights it on open.
    var preselected: HetznerKit.Image? = nil
    var onPick: (HetznerKit.Image) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: HetznerKit.Image?

    /// System images matching this server's architecture, grouped by
    /// `osFlavor` (ubuntu, debian, fedora, ...), flavors alphabetized.
    private var systemGroups: [(flavor: String, images: [HetznerKit.Image])] {
        let system = images.filter { $0.type == .system && $0.architecture == server.serverType.architecture }
        let grouped = Dictionary(grouping: system, by: \.osFlavor)
        return grouped
            .map { (flavor: $0.key, images: $0.value.sorted { $0.description < $1.description }) }
            .sorted { $0.flavor < $1.flavor }
    }

    private var snapshots: [HetznerKit.Image] {
        images.filter { $0.type == .snapshot }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                SheetHeaderBadge(systemImage: "arrow.triangle.2.circlepath", tint: HetzlyColors.destructive)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rebuild Server")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(server.name)
                        .caption()
                }
                Spacer()
            }

            Label(
                "Rebuilding destroys all data on the disk and reinstalls from the chosen image.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(HetzlyColors.destructive)
            .fixedSize(horizontal: false, vertical: true)

            imageList

            HStack(spacing: Spacing.unit * 3) {
                Button("Cancel") { dismiss() }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)

                DestructiveCTA(title: "Continue") {
                    guard let selection else { return }
                    dismiss()
                    onPick(selection)
                }
                .frame(maxWidth: .infinity)
                .disabled(selection == nil)
            }
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
        .onAppear { selection = preselected }
    }

    @ViewBuilder
    private var imageList: some View {
        switch imagesState {
        case .idle, .loading:
            VStack(spacing: Spacing.unit * 2) {
                Spacer()
                ProgressView()
                Text("Loading images…").caption()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .failed(let message):
            VStack {
                Spacer()
                Text(message).bodySecondary().multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                    if !snapshots.isEmpty {
                        SectionLabel("Your Snapshots")
                        GlassCard {
                            rows(snapshots) { snapshot in
                                (snapshot.description, snapshotSubtitle(snapshot))
                            }
                        }
                    }

                    ForEach(systemGroups, id: \.flavor) { group in
                        SectionLabel(group.flavor)
                        GlassCard {
                            rows(group.images) { image in
                                (image.description, image.name ?? "")
                            }
                        }
                    }
                }
            }
        }
    }

    private func rows(
        _ images: [HetznerKit.Image],
        content: @escaping (HetznerKit.Image) -> (title: String, subtitle: String)
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                if index > 0 {
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                }
                let labels = content(image)
                imageRow(image, title: labels.title, subtitle: labels.subtitle)
            }
        }
    }

    private func imageRow(_ image: HetznerKit.Image, title: String, subtitle: String) -> some View {
        Button {
            withAnimation(.snappy) { selection = image }
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: selection?.id == image.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(selection?.id == image.id ? HetzlyColors.accent : HetzlyColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .bodyPrimary()
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .caption()
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func snapshotSubtitle(_ snapshot: HetznerKit.Image) -> String {
        var parts: [String] = []
        if let size = snapshot.imageSize {
            parts.append(ServerDetailSupport.gigabytes(size))
        }
        parts.append(snapshot.created.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        RebuildSheet(
            server: PreviewFixtures.server,
            images: [PreviewFixtures.snapshot, PreviewFixtures.systemImage, PreviewFixtures.debianImage],
            imagesState: .loaded
        ) { _ in }
    }
}

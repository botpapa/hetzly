import HetznerKit
import SwiftUI

/// Sheet for attaching/detaching ISOs: a search field over `listISOs`, with
/// attach handing back to the confirm flow (warning: the server boots from
/// the ISO on its next restart) and a detach row when one is attached.
///
/// Attached-state limitation: the binding `Server` model has no `iso` field
/// (CONTRACTS.md), so "attached" is derived from the view model's
/// session-local `locallyAttachedISO` (set by a successful attach, cleared
/// by detach). ISOs attached before this session or from elsewhere won't
/// show here — the Detach row is still always reachable via the toggle at
/// the top so users can detach blind.
struct ServerISOSheet: View {
    let serverName: String
    let isos: [ISO]
    let isosState: ServerDetailViewModel.LoadState
    let attachedISO: ISO?
    var onAttach: (ISO) -> Void
    var onDetach: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredISOs: [ISO] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return isos }
        return isos.filter { iso in
            (iso.name?.lowercased().contains(query) ?? false)
                || (iso.description?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 4) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "opticaldiscdrive")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ISO Images")
                        .bodyPrimary()
                        .fontWeight(.semibold)
                    Text(serverName)
                        .caption()
                }
                Spacer()
            }

            if let attachedISO {
                attachedCard(attachedISO)
            } else {
                Button(action: { dismiss(); onDetach() }) {
                    Label("Detach current ISO (if any)", systemImage: "eject")
                        .caption()
                }
                .buttonStyle(.plain)
            }

            searchField

            Label(
                "After attaching, the server boots from the ISO on its next restart.",
                systemImage: "exclamationmark.triangle"
            )
            .caption()
            .fixedSize(horizontal: false, vertical: true)

            isoList
        }
        .padding(Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground { CanvasBackground() }
        .presentationCornerRadius(Radius.card)
    }

    private func attachedCard(_ iso: ISO) -> some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: "opticaldiscdrive.fill")
                    .foregroundStyle(HetzlyColors.statusTransitioning)
                VStack(alignment: .leading, spacing: 2) {
                    Text(iso.name ?? iso.description ?? "Attached ISO")
                        .bodySecondary()
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .lineLimit(1)
                    Text("Attached this session")
                        .caption()
                }
                Spacer()
                Button("Detach") {
                    dismiss()
                    onDetach()
                }
                .secondaryCTAStyle()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.unit * 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HetzlyColors.textTertiary)
            TextField("Search ISOs", text: $searchText)
                .bodyPrimary()
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(Spacing.unit * 3)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private var isoList: some View {
        switch isosState {
        case .idle, .loading:
            VStack(spacing: Spacing.unit * 2) {
                Spacer()
                ProgressView()
                Text("Loading ISOs…").caption()
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
            if filteredISOs.isEmpty {
                VStack {
                    Spacer()
                    Text("No ISOs match \"\(searchText)\".").caption()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(filteredISOs.enumerated()), id: \.element.id) { index, iso in
                                if index > 0 {
                                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.2))
                                }
                                isoRow(iso)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isoRow(_ iso: ISO) -> some View {
        Button {
            dismiss()
            onAttach(iso)
        } label: {
            HStack(spacing: Spacing.unit * 3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(iso.name ?? "ISO #\(iso.id)")
                        .bodySecondary()
                        .foregroundStyle(HetzlyColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let description = iso.description, !description.isEmpty {
                        Text(description)
                            .caption()
                            .lineLimit(1)
                    }
                }
                Spacer()
                if iso.deprecation != nil {
                    GlassChip("Deprecated")
                }
                Image(systemName: "plus.circle")
                    .foregroundStyle(HetzlyColors.accent)
            }
            .padding(.vertical, Spacing.unit * 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ServerISOSheet(
            serverName: "hetzi-prod-01",
            isos: [PreviewFixtures.iso],
            isosState: .loaded,
            attachedISO: nil,
            onAttach: { _ in },
            onDetach: {}
        )
    }
}

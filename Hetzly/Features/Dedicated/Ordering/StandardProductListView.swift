import SwiftUI

/// The "Standard" tab: configurable, built-to-order products at a fixed
/// monthly price. Search-only (no filter sheet — the catalog is small
/// enough, unlike the market's dozens of ever-changing auction listings).
struct StandardProductListView: View {
    @Environment(AppContainer.self) private var container

    var viewModel: OrderFlowViewModel
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchField

            switch viewModel.standardState {
            case .idle, .loading:
                if viewModel.standardListings.isEmpty { loadingState } else { list }
            case .failed(let message):
                if viewModel.standardListings.isEmpty { errorState(message) } else { list }
            case .loaded:
                if viewModel.standardListings.isEmpty {
                    emptyState
                } else if viewModel.filteredStandardListings.isEmpty {
                    noMatchesState
                } else {
                    list
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.unit * 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(HetzlyColors.textTertiary)
            TextField("Search products", text: Bindable(viewModel).standardSearchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Spacing.unit * 3)
        .padding(.vertical, Spacing.unit * 2.5)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.unit * 2)
    }

    private var list: some View {
        List {
            ForEach(viewModel.filteredStandardListings) { listing in
                Button {
                    onSelect(listing.id)
                } label: {
                    StandardProductRow(listing: listing)
                }
                .buttonStyle(.plain)
                .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.loadStandardProducts(container: container) }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading products…").caption()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .alarm, scale: 3)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.statusError)
            }
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            Button("Try Again") { Task { await viewModel.loadStandardProducts(container: container) } }
                .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 3)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Text("No standard products available for this account right now.")
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 3)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            Text("No products match \"\(viewModel.standardSearchText)\".")
                .bodySecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            StandardProductListView(viewModel: OrderPreviewFixtures.loadedViewModel(tab: .standard), onSelect: { _ in })
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

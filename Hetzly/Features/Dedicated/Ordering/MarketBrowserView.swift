import SwiftUI

/// The "Server Market" tab: search field, filter sheet trigger, sort menu,
/// and the filtered/sorted list of auction listings. All filtering/sorting
/// is client-side over the already-fetched catalog (Robot's 5-minute
/// response cache + ~150 req/h budget rule out server-side re-fetching per
/// keystroke).
struct MarketBrowserView: View {
    @Environment(AppContainer.self) private var container

    var viewModel: OrderFlowViewModel
    var onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            searchAndControls

            switch viewModel.marketState {
            case .idle, .loading:
                if viewModel.marketListings.isEmpty { loadingState } else { list }
            case .failed(let message):
                if viewModel.marketListings.isEmpty { errorState(message) } else { list }
            case .loaded:
                if viewModel.marketListings.isEmpty {
                    emptyState
                } else if viewModel.filteredSortedMarketListings.isEmpty {
                    noMatchesState
                } else {
                    list
                }
            }
        }
        .sheet(isPresented: Bindable(viewModel).isMarketFilterPresented) {
            MarketFilterSheet(filter: Bindable(viewModel).marketFilter)
        }
    }

    private var searchAndControls: some View {
        HStack(spacing: Spacing.unit * 2) {
            HStack(spacing: Spacing.unit * 2) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(HetzlyColors.textTertiary)
                TextField("Search CPU or name", text: Bindable(viewModel).marketSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, Spacing.unit * 3)
            .padding(.vertical, Spacing.unit * 2.5)
            .background {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }

            Button {
                viewModel.isMarketFilterPresented = true
            } label: {
                Image(systemName: viewModel.marketFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Filter")

            Menu {
                Picker("Sort", selection: Bindable(viewModel).marketSort) {
                    ForEach(MarketSort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Sort")
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.bottom, Spacing.unit * 2)
    }

    private var list: some View {
        List {
            ForEach(viewModel.filteredSortedMarketListings) { listing in
                Button {
                    onSelect(listing.id)
                } label: {
                    MarketProductRow(listing: listing)
                }
                .buttonStyle(.plain)
                .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await refresh() }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .idle, scale: 3)
            Text("Loading the market…").caption()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .alarm, scale: 3)
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
            Button("Try Again") { Task { await refresh() } }
                .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .peek, scale: 3)
            Text("No auction servers available right now.")
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin * 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: Spacing.unit * 4) {
            MascotView(state: .peek, scale: 3)
            Text("Nothing matches your filters.")
                .bodySecondary()
            Button("Clear Filters") {
                withAnimation(.snappy) { viewModel.marketFilter = MarketFilter() }
            }
            .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() async {
        await viewModel.loadMarketProducts(container: container)
    }
}

#Preview {
    NavigationStack {
        ZStack {
            CanvasBackground()
            MarketBrowserView(viewModel: OrderPreviewFixtures.loadedViewModel(), onSelect: { _ in })
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

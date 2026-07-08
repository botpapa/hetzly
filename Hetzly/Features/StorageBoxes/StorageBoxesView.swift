import HetznerKit
import SwiftUI

/// Entry point for Storage Boxes: an account-scoped list, mirroring
/// `DedicatedView` (Robot's account-scoped equivalent). Binding entry point
/// per `CONTRACTS.md` — reads `AppContainer` from the environment and owns
/// its own `NavigationStack`. The integrator wires this into
/// `ResourcesHubView`; this file does not touch that view.
struct StorageBoxesView: View {
    @Environment(AppContainer.self) private var container
    @State private var viewModel = StorageBoxListViewModel()
    @State private var selectedAccountID: UUID?

    init() {}

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                if container.storageBoxAccountsStore.accounts.isEmpty {
                    noAccountsState
                } else {
                    content
                }
            }
            .navigationTitle("Storage Boxes")
            .navigationDestination(for: StorageBoxRoute.self) { route in
                StorageBoxDetailView(route: route)
            }
            .toolbar {
                if container.storageBoxAccountsStore.accounts.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        StorageBoxAccountPickerChip(
                            accounts: container.storageBoxAccountsStore.accounts,
                            selection: $selectedAccountID
                        )
                    }
                }
            }
        }
        .task {
            if selectedAccountID == nil {
                selectedAccountID = container.storageBoxAccountsStore.accounts.first?.id
            }
            await viewModel.load(accountID: selectedAccountID, container: container)
        }
        .onChange(of: selectedAccountID) { _, newValue in
            Task { await viewModel.load(accountID: newValue, container: container) }
        }
        .onChange(of: container.storageBoxAccountsStore.accounts.map(\.id)) { _, ids in
            guard !ids.isEmpty else {
                selectedAccountID = nil
                return
            }
            if let selectedAccountID, !ids.contains(selectedAccountID) {
                self.selectedAccountID = ids.first
            } else if selectedAccountID == nil {
                selectedAccountID = ids.first
            }
        }
    }

    // MARK: - No accounts

    private var noAccountsState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "externaldrive")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Storage Box Accounts")
                Text("Add your Storage Box API token in Settings to see your Storage Boxes.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            if viewModel.boxes.isEmpty {
                ResourceLoadingState()
            } else {
                boxList
            }
        case .failed(let message):
            if viewModel.boxes.isEmpty {
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
                    Button("Try Again") {
                        Task { await viewModel.load(accountID: selectedAccountID, container: container) }
                    }
                    .secondaryCTAStyle()
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Spacing.unit * 16)
            } else {
                boxList
            }
        case .loaded:
            if viewModel.boxes.isEmpty {
                emptyBoxesState
            } else {
                boxList
            }
        }
    }

    private var emptyBoxesState: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
            VStack(spacing: Spacing.unit * 2) {
                SectionLabel("No Storage Boxes")
                Text("This account has no Storage Boxes yet.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }

    @ViewBuilder
    private var boxList: some View {
        if let accountID = selectedAccountID {
            ScrollView {
                LazyVStack(spacing: Spacing.unit * 3) {
                    ForEach(viewModel.boxes) { box in
                        NavigationLink(value: StorageBoxRoute(accountID: accountID, storageBoxID: box.id)) {
                            StorageBoxRow(box: box)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.screenMargin)
                .padding(.vertical, Spacing.screenMargin)
            }
            .refreshable {
                await viewModel.load(accountID: accountID, container: container)
            }
        }
    }
}

#Preview {
    StorageBoxesView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

import HetznerKit
import SwiftUI

/// Past and in-flight order transactions for a Robot account. Pushed from
/// `OrderServerFlow`'s toolbar clock icon. Manual pull-to-refresh only — no
/// background polling, per the M3 Robot rate-budget constraint.
struct TransactionsListView: View {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private enum Source {
        case live(accountID: UUID)
        case preview([TransactionSummary])
    }

    @Environment(AppContainer.self) private var container
    @State private var loadState: LoadState = .idle
    @State private var transactions: [TransactionSummary] = []

    private let source: Source

    init(accountID: UUID) {
        source = .live(accountID: accountID)
    }

    /// Preview/test-only entry point: seeds the list directly, no network.
    init(previewTransactions: [TransactionSummary]) {
        source = .preview(previewTransactions)
        _transactions = State(initialValue: previewTransactions)
        _loadState = State(initialValue: .loaded)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle("Order History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard case .idle = loadState else { return }
            await load()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .idle, .loading:
            if transactions.isEmpty { loadingState } else { list }
        case .failed(let message):
            if transactions.isEmpty { errorState(message) } else { list }
        case .loaded:
            if transactions.isEmpty { emptyState } else { list }
        }
    }

    private var list: some View {
        List {
            ForEach(transactions) { transaction in
                TransactionRow(transaction: transaction)
                    .plainRow()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await load() }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading order history…").caption()
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
            Button("Try Again") { Task { await load() } }
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
            Text("No orders yet.")
                .bodySecondary()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard case .live(let accountID) = source else { return }
        guard let client = container.robotClient(for: accountID) else {
            loadState = .failed("No stored credentials for this Robot account.")
            return
        }
        if transactions.isEmpty { loadState = .loading }
        do {
            let loaded = try await client.listTransactions()
            transactions = loaded.map(RobotOrderingMapping.summary).sorted { $0.date > $1.date }
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? HetznerAPIError {
            return apiError.userMessage
        }
        return "Something went wrong. Please try again."
    }
}

#Preview {
    NavigationStack {
        TransactionsListView(previewTransactions: OrderPreviewFixtures.transactions)
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    NavigationStack {
        TransactionsListView(previewTransactions: [])
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

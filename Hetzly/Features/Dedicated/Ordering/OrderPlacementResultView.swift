import SwiftUI

/// Content shown once order placement has started — replaces the review
/// form entirely for `.authenticating`/`.placing`/`.succeeded`/`.failed`,
/// mirroring `CreateServerResultView`'s role for the create-server wizard.
struct OrderPlacementResultView: View {
    @Environment(AppContainer.self) private var container

    var viewModel: OrderFlowViewModel
    var onDone: () -> Void = {}

    /// Shown from the ambiguous-failure warning's "Check Order History"
    /// button — a modal sheet rather than a push since this view can itself
    /// be reached mid-`NavigationStack` and a push here would fight with
    /// `OrderReviewView`'s own title/back button.
    @State private var isOrderHistoryPresented = false

    var body: some View {
        VStack(spacing: Spacing.unit * 6) {
            Spacer(minLength: 0)

            switch viewModel.placementPhase {
            case .idle:
                EmptyView()
            case .authenticating:
                statusContent(state: .work, title: "Confirming with Face ID…")
            case .placing:
                statusContent(state: .work, title: "Placing your order…")
            case .succeeded(let transaction):
                succeededContent(transaction)
            case .failed(let error):
                failedContent(error)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isOrderHistoryPresented) {
            NavigationStack {
                TransactionsListView(accountID: viewModel.accountID)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { isOrderHistoryPresented = false }
                        }
                    }
            }
        }
    }

    private func statusContent(state: MascotState, title: String) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: state, scale: 3)
            } else {
                mascotFallback(for: state)
            }
            Text(title)
                .bodyPrimary()
            ProgressView()
                .tint(HetzlyColors.accent)
        }
    }

    /// SF Symbol substitute shown when the mascot is disabled, matched to the
    /// same intent as the `MascotState` it replaces.
    @ViewBuilder
    private func mascotFallback(for state: MascotState) -> some View {
        switch state {
        case .idle, .walk, .run, .sleep:
            ProgressView().controlSize(.large)
        case .alarm:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(HetzlyColors.statusError)
        case .celebrate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(HetzlyColors.statusRunning)
        case .work:
            Image(systemName: "gearshape.fill")
                .font(.system(size: 40))
                .foregroundStyle(HetzlyColors.textSecondary)
        case .peek:
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(HetzlyColors.textTertiary)
        }
    }

    // MARK: - Succeeded

    private func succeededContent(_ transaction: TransactionSummary) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .celebrate, scale: 3)
            } else {
                mascotFallback(for: .celebrate)
            }

            VStack(spacing: Spacing.unit) {
                Text("Order Placed").font(.system(size: 20, weight: .semibold)).foregroundStyle(HetzlyColors.textPrimary)
                Text(transaction.productName).bodySecondary()
            }

            GlassCard {
                VStack(spacing: Spacing.unit * 3) {
                    HStack {
                        Text("Transaction").caption()
                        Spacer()
                        Text(transaction.id).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textPrimary)
                    }
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                    HStack {
                        Text("Status").caption()
                        Spacer()
                        HStack(spacing: Spacing.unit) {
                            StatusDot(transaction.status.resourceStatus)
                            Text(transaction.status.displayText).bodySecondary()
                        }
                    }
                    if let serverNumber = transaction.serverNumber {
                        Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                        HStack {
                            Text("Server #").caption()
                            Spacer()
                            Text("\(serverNumber)").hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textPrimary)
                        }
                    }
                }
            }

            Text("It'll appear in your Dedicated server list once Hetzner finishes provisioning it.")
                .caption()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            PrimaryCTA(title: "Done") { viewModel.resetPlacement(); onDone() }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Failed

    @ViewBuilder
    private func failedContent(_ error: OrderPlacementError) -> some View {
        switch error {
        case .orderingDisabled:
            orderingDisabledContent
        case .message(let message, let isAmbiguous):
            VStack(spacing: Spacing.unit * 5) {
                if container.settings.mascotEnabled {
                    MascotView(state: .alarm, scale: 3)
                } else {
                    mascotFallback(for: .alarm)
                }
                Text("Couldn't place the order").font(.system(size: 18, weight: .semibold)).foregroundStyle(HetzlyColors.textPrimary)
                Text(message)
                    .bodySecondary()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.screenMargin)
                if isAmbiguous {
                    ambiguousFailureWarning
                }
                PrimaryCTA(title: "Try Again") { viewModel.retryPlacement() }
            }
        }
    }

    /// Shown only for transport-level/timeout failures, where the request
    /// may have reached Hetzner and been processed even though this device
    /// never saw a clean response — retrying blind could double-order.
    private var ambiguousFailureWarning: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack(alignment: .top, spacing: Spacing.unit * 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(HetzlyColors.statusError)
                    Text("Your previous attempt may have gone through — check Order History first.")
                        .bodySecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Check Order History") { isOrderHistoryPresented = true }
                    .secondaryCTAStyle()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var orderingDisabledContent: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .alarm, scale: 3)
            } else {
                mascotFallback(for: .alarm)
            }
            Text("Ordering Isn't Enabled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HetzlyColors.textPrimary)

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    Text("Ordering isn't enabled for this Robot account. Enable it in Robot → Settings → Preferences → Ordering, then try again.")
                        .bodySecondary()
                        .fixedSize(horizontal: false, vertical: true)
                    Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                    VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                        Text("1. Open robot.hetzner.com and sign in.").caption()
                        Text("2. Go to Settings → Preferences.").caption()
                        Text("3. Turn on \"Ordering of servers\".").caption()
                        Text("4. Come back here and try again.").caption()
                    }
                }
            }

            PrimaryCTA(title: "Try Again") { viewModel.retryPlacement() }
        }
    }
}

#Preview("Placing") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(viewModel: OrderPreviewFixtures.reviewViewModel(phase: .placing))
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

#Preview("Succeeded") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(viewModel: OrderPreviewFixtures.reviewViewModel(phase: .succeeded(OrderPreviewFixtures.transactions[0])))
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

#Preview("Ordering Disabled") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(viewModel: OrderPreviewFixtures.reviewViewModel(phase: .failed(.orderingDisabled)))
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(
            viewModel: OrderPreviewFixtures.reviewViewModel(phase: .failed(.message("This product is temporarily out of stock.")))
        )
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

#Preview("Failed — ambiguous") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(
            viewModel: OrderPreviewFixtures.reviewViewModel(
                phase: .failed(.message("A network error occurred. Please check your connection and try again.", isAmbiguous: true))
            )
        )
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

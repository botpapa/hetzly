import SwiftUI

/// Content shown once order placement has started — replaces the review
/// form entirely for `.authenticating`/`.placing`/`.succeeded`/`.failed`,
/// mirroring `CreateServerResultView`'s role for the create-server wizard.
struct OrderPlacementResultView: View {
    var viewModel: OrderFlowViewModel
    var onDone: () -> Void = {}

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
    }

    private func statusContent(state: MascotState, title: String) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: state, scale: 3)
            Text(title)
                .bodyPrimary()
            ProgressView()
                .tint(HetzlyColors.accent)
        }
    }

    // MARK: - Succeeded

    private func succeededContent(_ transaction: TransactionSummary) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .celebrate, scale: 3)

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
        case .message(let message):
            VStack(spacing: Spacing.unit * 5) {
                MascotView(state: .alarm, scale: 3)
                Text("Couldn't place the order").font(.system(size: 18, weight: .semibold)).foregroundStyle(HetzlyColors.textPrimary)
                Text(message)
                    .bodySecondary()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.screenMargin)
                PrimaryCTA(title: "Try Again") { viewModel.retryPlacement() }
            }
        }
    }

    private var orderingDisabledContent: some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .alarm, scale: 3)
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
    .preferredColorScheme(.dark)
}

#Preview("Succeeded") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(viewModel: OrderPreviewFixtures.reviewViewModel(phase: .succeeded(OrderPreviewFixtures.transactions[0])))
    }
    .preferredColorScheme(.dark)
}

#Preview("Ordering Disabled") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(viewModel: OrderPreviewFixtures.reviewViewModel(phase: .failed(.orderingDisabled)))
    }
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    ZStack {
        CanvasBackground()
        OrderPlacementResultView(
            viewModel: OrderPreviewFixtures.reviewViewModel(phase: .failed(.message("This product is temporarily out of stock.")))
        )
    }
    .preferredColorScheme(.dark)
}

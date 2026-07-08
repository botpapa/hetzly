import SwiftUI

/// The deliberate final step, per CONTRACTS.md (non-negotiable): restate
/// everything, require an explicit armed toggle before the CTA even enables,
/// then Face ID (always, regardless of the destructive-actions setting —
/// this is real money), then place. Morphs into `OrderPlacementResultView`
/// in place once placement starts, mirroring `CreateServerFlow`'s
/// phase-driven content swap rather than pushing another route.
struct OrderReviewView: View {
    @Environment(AppContainer.self) private var container

    var viewModel: OrderFlowViewModel
    var onDone: () -> Void = {}

    var body: some View {
        Group {
            switch viewModel.placementPhase {
            case .idle:
                reviewContent
            case .authenticating, .placing, .succeeded, .failed:
                OrderPlacementResultView(viewModel: viewModel, onDone: onDone)
            }
        }
        .navigationTitle("Review Order")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(viewModel.placementPhase.isInFlight)
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let draft = viewModel.draft {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.unit * 5) {
                    summaryCard(draft)
                    configCard(draft)
                    PriceBreakdownCard(
                        monthlyNet: draft.monthlyNet,
                        monthlyGross: draft.monthlyGross,
                        setupNet: draft.setupNet,
                        setupGross: draft.setupGross,
                        currency: draft.currency
                    )
                    disclaimerCard
                    armToggle
                }
                .padding(Spacing.screenMargin)
                .padding(.bottom, Spacing.unit * 10)
            }
            .safeAreaInset(edge: .bottom) {
                footer(draft)
            }
        } else {
            VStack(spacing: Spacing.unit * 4) {
                if container.settings.mascotEnabled {
                    MascotView(state: .alarm, scale: 3)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(HetzlyColors.statusError)
                }
                Text("Nothing to review — go back and pick a product first.")
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summaryCard(_ draft: OrderDraft) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Product")
                Text(draft.displayName)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(HetzlyColors.textPrimary)
                Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
                HStack {
                    Text("Bills to").caption()
                    Spacer()
                    Text(viewModel.accountUsername).hetzlyMonoNumbers().foregroundStyle(HetzlyColors.textSecondary)
                }
                if !viewModel.accountLabel.isEmpty {
                    HStack {
                        Text("Robot account").caption()
                        Spacer()
                        Text(viewModel.accountLabel).bodySecondary()
                    }
                }
            }
        }
    }

    private func configCard(_ draft: OrderDraft) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                SectionLabel("Configuration")
                if let dist = draft.dist {
                    configRow(title: "Operating System", value: dist)
                }
                if let location = draft.location {
                    configRow(title: "Location", value: location)
                }
                configRow(title: "SSH Keys", value: draft.sshKeys.map(\.name).joined(separator: ", "))
            }
        }
    }

    private func configRow(title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).caption()
            Spacer()
            Text(value)
                .bodySecondary()
                .multilineTextAlignment(.trailing)
        }
    }

    private var disclaimerCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Spacing.unit * 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HetzlyColors.accent)
                Text("This places a binding order with Hetzner Online GmbH and incurs real charges.")
                    .bodySecondary()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var armToggle: some View {
        GlassCard {
            Toggle(isOn: Bindable(viewModel).isArmed) {
                Text("I understand this is a real, paid order")
                    .bodyPrimary()
                    .fontWeight(.semibold)
            }
            .tint(HetzlyColors.accent)
        }
    }

    private func footer(_ draft: OrderDraft) -> some View {
        VStack(spacing: Spacing.unit * 2) {
            Divider().overlay(HetzlyColors.textTertiary.opacity(0.15))
            PrimaryCTA(title: placeOrderTitle(draft)) {
                Task { await viewModel.placeOrder(container: container) }
            }
            .disabled(!viewModel.isArmed)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.unit * 2)
        .padding(.bottom, Spacing.unit * 3)
        .glassFooterBackground()
    }

    private func placeOrderTitle(_ draft: OrderDraft) -> String {
        let monthly = OrderCurrencyFormat.string(draft.monthlyGross, currencyCode: draft.currency)
        let setup = OrderCurrencyFormat.string(draft.setupGross, currencyCode: draft.currency)
        return "Place Order · \(monthly)/mo + \(setup) setup"
    }
}

#Preview("Review") {
    NavigationStack {
        ZStack {
            CanvasBackground()
            OrderReviewView(viewModel: OrderPreviewFixtures.reviewViewModel())
        }
    }
    .environment(AppContainer.makeDefault())
    .preferredColorScheme(.dark)
}

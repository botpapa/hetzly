import HetznerKit
import SwiftUI

/// Firewall detail: INBOUND / OUTBOUND rule sections (tap to edit, swipe to
/// delete, "Add rule" per section), the APPLIED TO chip list, and a delete
/// affordance handled by the pushing list view. All rule mutations replace
/// the full rule set via `setFirewallRules`, so each section shows a single
/// saving overlay while a change is in flight.
struct FirewallDetailView: View {
    let projectID: UUID
    let firewallID: Int
    var initialFirewall: Firewall?

    @Environment(AppContainer.self) private var container

    @State private var viewModel: FirewallDetailViewModel?
    @State private var editingContext: RuleEditContext?
    @State private var isApplySheetPresented = false
    @State private var pendingRuleDeletion: PendingRuleDeletion?

    init(projectID: UUID, firewallID: Int, initialFirewall: Firewall? = nil) {
        self.projectID = projectID
        self.firewallID = firewallID
        self.initialFirewall = initialFirewall
    }

    /// Which rule the edit sheet is operating on: a new rule for a fixed
    /// direction, or an existing one at an index within that direction.
    private struct RuleEditContext: Identifiable {
        let direction: FirewallDirection
        let index: Int?
        let rule: FirewallRule?

        var id: String { "\(direction.rawValue)-\(index.map(String.init) ?? "new")" }
    }

    private struct PendingRuleDeletion: Identifiable {
        let direction: FirewallDirection
        let index: Int
        let rule: FirewallRule

        var id: String { "\(direction.rawValue)-\(index)" }
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .navigationTitle(viewModel?.firewall?.name ?? "Firewall")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard viewModel == nil else { return }
            let model = FirewallDetailViewModel(
                projectID: projectID,
                firewallID: firewallID,
                container: container,
                initial: initialFirewall
            )
            viewModel = model
            await model.load()
        }
        .sheet(item: $editingContext) { context in
            RuleEditSheet(
                direction: context.direction,
                existingRule: context.rule,
                onSave: { rule in
                    editingContext = nil
                    Task {
                        if let index = context.index {
                            await viewModel?.updateRule(at: index, direction: context.direction, with: rule)
                        } else {
                            await viewModel?.addRule(rule)
                        }
                    }
                },
                onCancel: { editingContext = nil }
            )
        }
        .sheet(isPresented: $isApplySheetPresented) {
            ApplyToServerSheet(
                servers: viewModel?.servers ?? [],
                alreadyAppliedIDs: viewModel?.appliedServerIDs ?? [],
                onApply: { serverIDs in
                    isApplySheetPresented = false
                    Task { await viewModel?.apply(toServerIDs: serverIDs) }
                },
                onCancel: { isApplySheetPresented = false }
            )
        }
        .confirmationDialog(
            "Delete Rule",
            isPresented: Binding(
                get: { pendingRuleDeletion != nil },
                set: { if !$0 { pendingRuleDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Rule", role: .destructive) {
                guard let pending = pendingRuleDeletion else { return }
                pendingRuleDeletion = nil
                Task { await viewModel?.deleteRule(at: pending.index, direction: pending.direction) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Traffic matched by this rule will no longer be allowed.")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let viewModel {
            switch viewModel.loadState {
            case .idle, .loading:
                if viewModel.firewall == nil {
                    loadingState
                } else {
                    loadedContent(viewModel)
                }
            case .failed(let message):
                if viewModel.firewall != nil {
                    loadedContent(viewModel)
                } else {
                    errorState(message)
                }
            case .loaded:
                loadedContent(viewModel)
            }
        } else {
            loadingState
        }
    }

    private var loadingState: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading firewall…").caption()
        }
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
            Button("Try Again") {
                Task { await viewModel?.load() }
            }
            .secondaryCTAStyle()
        }
    }

    private func loadedContent(_ viewModel: FirewallDetailViewModel) -> some View {
        List {
            if let actionError = viewModel.actionError {
                Text(actionError)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(HetzlyColors.destructive)
                    .plainRow()
            }

            ruleSection(
                title: "Inbound",
                direction: .inbound,
                rules: viewModel.inboundRules,
                isSaving: viewModel.isSavingRules
            )

            ruleSection(
                title: "Outbound",
                direction: .outbound,
                rules: viewModel.outboundRules,
                isSaving: viewModel.isSavingRules
            )

            appliedToSection(viewModel)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await viewModel.load() }
    }

    // MARK: - Rule sections

    private func ruleSection(
        title: String,
        direction: FirewallDirection,
        rules: [FirewallRule],
        isSaving: Bool
    ) -> some View {
        Section {
            if rules.isEmpty {
                Text(direction == .inbound
                    ? "No inbound rules — all inbound traffic is blocked."
                    : "No outbound rules — all outbound traffic is allowed.")
                    .caption()
                    .plainRow()
            } else {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    Button {
                        guard !isSaving else { return }
                        editingContext = RuleEditContext(direction: direction, index: index, rule: rule)
                    } label: {
                        FirewallRuleRow(rule: rule)
                    }
                    .buttonStyle(.plain)
                    .plainRow()
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingRuleDeletion = PendingRuleDeletion(direction: direction, index: index, rule: rule)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .opacity(isSaving ? 0.55 : 1)
                }
            }

            Button {
                editingContext = RuleEditContext(direction: direction, index: nil, rule: nil)
            } label: {
                Label("Add Rule", systemImage: "plus.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .plainRow()
        } header: {
            HStack {
                SectionLabel(title)
                Spacer()
                if isSaving {
                    HStack(spacing: Spacing.unit) {
                        ProgressView().controlSize(.mini).tint(HetzlyColors.textSecondary)
                        Text("Saving…").caption()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin))
        }
    }

    // MARK: - Applied to

    private func appliedToSection(_ viewModel: FirewallDetailViewModel) -> some View {
        Section {
            AppliedToView(
                appliedTo: viewModel.firewall?.appliedTo ?? [],
                servers: viewModel.servers,
                isSaving: viewModel.isSavingAppliedTo,
                onApply: { isApplySheetPresented = true },
                onRemoveServer: { serverID in
                    Task { await viewModel.remove(fromServerID: serverID) }
                }
            )
            .plainRow()
        } header: {
            HStack {
                SectionLabel("Applied To")
                Spacer()
                if viewModel.isSavingAppliedTo {
                    HStack(spacing: Spacing.unit) {
                        ProgressView().controlSize(.mini).tint(HetzlyColors.textSecondary)
                        Text("Saving…").caption()
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.screenMargin, bottom: 0, trailing: Spacing.screenMargin))
        }
    }
}

#Preview {
    NavigationStack {
        FirewallDetailView(
            projectID: UUID(),
            firewallID: FirewallPreviewFixtures.webFirewall.id,
            initialFirewall: FirewallPreviewFixtures.webFirewall
        )
        .environment(AppContainer.makeDefault())
    }
    .preferredColorScheme(.dark)
}

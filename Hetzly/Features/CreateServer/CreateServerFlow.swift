import HetznerKit
import SwiftUI

/// The app's "buy" flow: a single flowing sheet that walks through four
/// steps (location, image, type, configuration) and morphs its content in
/// place with `.snappy` transitions rather than pushing onto a
/// `NavigationStack`. Binding entry point per `CONTRACTS.md`'s M2 Wave B
/// contracts — presented with `.sheet(...) { CreateServerFlow(...) }` by
/// whichever screen offers "Create Server".
struct CreateServerFlow: View {
    let projectID: UUID
    let onCreated: (Server) -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: CreateServerViewModel

    init(projectID: UUID, onCreated: @escaping (Server) -> Void) {
        self.projectID = projectID
        self.onCreated = onCreated
        _viewModel = State(initialValue: CreateServerViewModel(projectID: projectID))
    }

    /// Preview/test-only entry point: injects a pre-populated view model so
    /// previews never touch the network or need a real `AppContainer` load.
    init(previewViewModel: CreateServerViewModel, onCreated: @escaping (Server) -> Void = { _ in }) {
        self.projectID = previewViewModel.projectID
        self.onCreated = onCreated
        _viewModel = State(initialValue: previewViewModel)
    }

    var body: some View {
        ZStack {
            CanvasBackground()
            content
        }
        .interactiveDismissDisabled(viewModel.phase.isCreating)
        .task {
            guard viewModel.catalogState == .idle else { return }
            await viewModel.loadCatalog(container: container)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .configuring:
            configuringContent
        case .creating, .succeeded, .failed:
            CreateServerResultView(
                viewModel: viewModel,
                onDone: { server in
                    onCreated(server)
                    dismiss()
                },
                onRetry: { viewModel.retryFromFailure() }
            )
        }
    }

    @ViewBuilder
    private var configuringContent: some View {
        switch viewModel.catalogState {
        case .idle, .loading:
            catalogLoadingView
        case .failed(let message):
            catalogFailedView(message)
        case .loaded:
            wizardContent
        }
    }

    private var catalogLoadingView: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading options…").caption()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func catalogFailedView(_ message: String) -> some View {
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
                Task { await viewModel.loadCatalog(container: container) }
            }
            .secondaryCTAStyle()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var wizardContent: some View {
        VStack(spacing: 0) {
            CreateServerStepHeader(
                step: viewModel.step,
                onBack: { withAnimation(.snappy) { viewModel.goBack() } },
                onCancel: { dismiss() }
            )
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.unit * 3)
            .padding(.bottom, Spacing.unit * 2)

            ScrollView {
                stepContent
                    .padding(.horizontal, Spacing.screenMargin)
                    .padding(.top, Spacing.unit * 2)
                    .padding(.bottom, Spacing.unit * 8)
            }

            CreateServerFooter(viewModel: viewModel) {
                if viewModel.step == .config {
                    Task { await viewModel.createServer(container: container) }
                } else {
                    withAnimation(.snappy) { viewModel.advance() }
                }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        Group {
            switch viewModel.step {
            case .location: LocationStepView(viewModel: viewModel)
            case .image: ImageStepView(viewModel: viewModel)
            case .type: ServerTypeStepView(viewModel: viewModel)
            case .config: ConfigStepView(viewModel: viewModel)
            }
        }
        .id(viewModel.step)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .move(edge: .trailing)),
                removal: .opacity.combined(with: .move(edge: .leading))
            )
        )
    }
}

#Preview("Step 1 — Location") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.viewModel(step: .location))
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Step 4 — Configure") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.configuredViewModel())
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Succeeded") {
    CreateServerFlow(previewViewModel: CreateServerPreviewFixtures.succeededViewModel(withRootPassword: true))
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

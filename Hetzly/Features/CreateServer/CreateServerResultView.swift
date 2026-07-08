import HetznerKit
import SwiftUI
import UIKit

/// Full-sheet content swap shown once server creation has started —
/// replaces the step wizard entirely for `.creating`/`.succeeded`/`.failed`.
/// `.configuring` renders nothing here (the wizard itself owns that phase).
struct CreateServerResultView: View {
    var viewModel: CreateServerViewModel
    var onDone: (Server) -> Void
    var onRetry: () -> Void

    @State private var ipCopied = false
    @State private var passwordCopied = false

    var body: some View {
        VStack(spacing: Spacing.unit * 6) {
            Spacer(minLength: 0)

            switch viewModel.phase {
            case .configuring:
                EmptyView()
            case .creating(let progress):
                creatingContent(progress: progress)
            case .succeeded(let server):
                succeededContent(server)
            case .failed(let message):
                failedContent(message)
            }

            Spacer(minLength: 0)
        }
        .padding(Spacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Creating

    private func creatingContent(progress: Int) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .work, scale: 3)
            Text("Creating server… \(progress)%")
                .hetzlyMonoNumbers()
                .foregroundStyle(HetzlyColors.textPrimary)
            ProgressView(value: Double(progress), total: 100)
                .tint(HetzlyColors.accent)
                .frame(maxWidth: 220)
        }
    }

    // MARK: - Succeeded

    private func succeededContent(_ server: Server) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .celebrate, scale: 3)

            VStack(spacing: Spacing.unit) {
                Text(server.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textPrimary)
                Text("is ready")
                    .bodySecondary()
            }

            if let ip = server.publicNet.ipv4?.ip {
                ipRow(ip)
            }

            if let password = viewModel.createdRootPassword {
                rootPasswordCard(password)
            }

            PrimaryCTA(title: "Done") { onDone(server) }
                .frame(maxWidth: .infinity)
        }
    }

    private func ipRow(_ ip: String) -> some View {
        Button {
            UIPasteboard.general.string = ip
            ipCopied = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                ipCopied = false
            }
        } label: {
            HStack(spacing: Spacing.unit * 2) {
                Text(ip).hetzlyMonoNumbers()
                Image(systemName: ipCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13))
            }
            .foregroundStyle(HetzlyColors.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func rootPasswordCard(_ password: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                Label("Root Password", systemImage: "key.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textSecondary)

                Text(password)
                    .hetzlyMonoNumbers()
                    .foregroundStyle(HetzlyColors.textPrimary)

                Button {
                    SensitivePasteboard.copy(password)
                    passwordCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        passwordCopied = false
                    }
                } label: {
                    Label(
                        passwordCopied ? "Copied — clears in 60s" : "Copy Password",
                        systemImage: passwordCopied ? "checkmark" : "doc.on.doc"
                    )
                }
                .secondaryCTAStyle()

                Text("This password won't be shown again. Store it somewhere safe.")
                    .caption()
            }
        }
    }

    // MARK: - Failed

    private func failedContent(_ message: String) -> some View {
        VStack(spacing: Spacing.unit * 5) {
            MascotView(state: .alarm, scale: 3)
            Text("Couldn't create the server")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HetzlyColors.textPrimary)
            Text(message)
                .bodySecondary()
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.screenMargin)
            PrimaryCTA(title: "Try Again", action: onRetry)
        }
    }
}

#Preview("Creating") {
    ZStack {
        CanvasBackground()
        CreateServerResultView(viewModel: CreateServerPreviewFixtures.creatingViewModel(), onDone: { _ in }, onRetry: {})
    }
    .preferredColorScheme(.dark)
}

#Preview("Succeeded — with password") {
    ZStack {
        CanvasBackground()
        CreateServerResultView(
            viewModel: CreateServerPreviewFixtures.succeededViewModel(withRootPassword: true),
            onDone: { _ in },
            onRetry: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Succeeded — SSH only") {
    ZStack {
        CanvasBackground()
        CreateServerResultView(
            viewModel: CreateServerPreviewFixtures.succeededViewModel(withRootPassword: false),
            onDone: { _ in },
            onRetry: {}
        )
    }
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    ZStack {
        CanvasBackground()
        CreateServerResultView(viewModel: CreateServerPreviewFixtures.failedViewModel(), onDone: { _ in }, onRetry: {})
    }
    .preferredColorScheme(.dark)
}

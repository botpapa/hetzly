import SwiftUI

/// The Invoices surface. Hetzner has no invoice API, so this is deliberately
/// honest about what it does: a one-time explainer (dismissable, persisted
/// via `@AppStorage`) and a single CTA that opens the official Hetzner
/// accounts portal in an out-of-process `SFSafariViewController` — the login
/// stays with Hetzner and never touches Hetzly. Binding entry point per the
/// M2 Wave B contract: `InvoicesView()`.
struct InvoicesView: View {
    @Environment(AppContainer.self) private var container

    @AppStorage("com.hetzly.invoices.explainerDismissed")
    private var explainerDismissed = false

    @State private var isPresentingPortal = false

    private var invoicesURL: URL {
        URL(string: "https://accounts.hetzner.com/invoice") ?? URL(fileURLWithPath: "/")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        if !explainerDismissed {
                            explainerCard
                                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        portalCard
                    }
                    .padding(Spacing.screenMargin)
                    .animation(.smooth, value: explainerDismissed)
                }
            }
            .navigationTitle("Invoices")
        }
        .fullScreenCover(isPresented: $isPresentingPortal) {
            SafariView(url: invoicesURL)
                .ignoresSafeArea()
        }
    }

    // MARK: - Explainer

    private var explainerCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                HStack(alignment: .top) {
                    if container.settings.mascotEnabled {
                        MascotView(state: .idle, scale: 2)
                    } else {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(HetzlyColors.accent)
                    }

                    Spacer()

                    Button {
                        explainerDismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(HetzlyColors.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color.white.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss explanation")
                }

                Text("Why a browser?")
                    .bodyPrimary()
                    .fontWeight(.semibold)

                Text(
                    "Hetzner provides no invoice API. This opens the official Hetzner "
                        + "accounts portal in a secure in-app browser — your login stays "
                        + "with Hetzner and never touches Hetzly."
                )
                .bodySecondary()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Portal CTA

    private var portalCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 4) {
                HStack(spacing: Spacing.unit * 3) {
                    Image(systemName: "doc.plaintext")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(HetzlyColors.accent)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .fill(HetzlyColors.accent.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hetzner accounts portal")
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        Text("accounts.hetzner.com")
                            .caption()
                            .hetzlyMonoNumbers()
                            .font(.system(size: 13, design: .monospaced))
                    }

                    Spacer(minLength: 0)
                }

                PrimaryCTA(title: "Open invoices") {
                    isPresentingPortal = true
                }
                .frame(maxWidth: .infinity)

                Label("Login handled entirely by Hetzner", systemImage: "lock.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
    }
}

#Preview {
    InvoicesView()
        .environment(AppContainer.makeDefault())
        .preferredColorScheme(.dark)
}

#Preview("Explainer dismissed") {
    InvoicesView()
        .environment(AppContainer.makeDefault())
        .onAppear {
            UserDefaults.standard.set(true, forKey: "com.hetzly.invoices.explainerDismissed")
        }
        .preferredColorScheme(.dark)
}

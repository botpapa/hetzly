import HetznerKit
import SwiftUI

// MARK: - Error / offline banners

/// Inline error banner matching the Dashboard's per-section error style:
/// a warning glyph plus a human `HetznerAPIError.userMessage`-shaped
/// sentence inside a `GlassCard`.
struct ResourceErrorBanner: View {
    let message: String

    var body: some View {
        GlassCard {
            HStack(spacing: Spacing.unit * 2) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(HetzlyColors.statusError)
                Text(message)
                    .bodySecondary()
            }
        }
    }
}

// MARK: - Empty state

/// Shared empty-state for every Resources list screen: Hetzi peeking, one
/// line of copy, and a primary CTA to create the first item.
struct ResourceEmptyState: View {
    let title: String
    let message: String
    let ctaTitle: String
    let onCreate: () -> Void

    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: Spacing.unit * 5) {
            if container.settings.mascotEnabled {
                MascotView(state: .peek, scale: 4)
            } else {
                Image(systemName: "tray")
                    .font(.system(size: 40))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }

            VStack(spacing: Spacing.unit * 2) {
                SectionLabel(title)
                Text(message)
                    .bodySecondary()
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: 280)

            PrimaryCTA(title: ctaTitle, action: onCreate)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 12)
    }
}

// MARK: - Loading state

struct ResourceLoadingState: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(spacing: Spacing.unit * 4) {
            if container.settings.mascotEnabled {
                MascotView(state: .idle, scale: 3)
            } else {
                ProgressView().controlSize(.large)
            }
            Text("Loading…").caption()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.unit * 16)
    }
}

// MARK: - Detail rows

/// A single label/value row used throughout detail screens. Values that read
/// as identifiers (IPs, fingerprints, CIDRs) should pass `monospaced: true`.
struct DetailInfoRow: View {
    let label: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack(alignment: .top) {
            Text(label).bodySecondary()
            Spacer(minLength: Spacing.unit * 4)
            Group {
                if monospaced {
                    Text(value).hetzlyMonoNumbers()
                } else {
                    Text(value).bodyPrimary()
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Formatting helpers

enum ResourceFormatting {
    /// Truncates a long monospaced identifier (fingerprint, key, hash) to
    /// `keep` characters on each side, e.g. `"SHA256:ab12…9f0z"`.
    static func truncatedMiddle(_ text: String, keep: Int = 10) -> String {
        guard text.count > keep * 2 + 1 else { return text }
        let prefix = text.prefix(keep)
        let suffix = text.suffix(keep)
        return "\(prefix)…\(suffix)"
    }

    static func dateString(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Very small, dependency-free IPv4 CIDR sanity check — good enough to
    /// stop obviously malformed input before it reaches the API, not a full
    /// RFC validator. Hetzner's own validation is the source of truth.
    static func isPlausibleIPv4CIDR(_ text: String) -> Bool {
        let parts = text.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let prefixLength = Int(parts[1]), (0...32).contains(prefixLength) else {
            return false
        }
        let octets = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard let value = Int(octet), (0...255).contains(value) else { return false }
            return true
        }
    }

    /// Rough monthly price hint for a Block Storage volume, from
    /// `Pricing.volumePerGBMonth`. Returns `nil` when pricing isn't loaded or
    /// unparsable — callers treat the hint as optional decoration.
    static func volumeMonthlyPriceHint(sizeGB: Int, pricing: Pricing?) -> String? {
        guard let perGB = pricing?.volumePerGBMonth?.netDecimal else { return nil }
        let total = perGB * Decimal(sizeGB)
        let formatted = total.formatted(.currency(code: pricing?.currency ?? "EUR"))
        return "≈ \(formatted)/mo"
    }
}

// MARK: - Section row on the hub

/// One resource-category row on `ResourcesHubView`: icon, title, and a
/// lazily-loaded count badge.
struct ResourceHubRow: View {
    let title: String
    let systemImage: String
    /// `nil` while the count hasn't loaded yet (shows a subtle placeholder
    /// instead of "0" so an empty category doesn't read as "still loading").
    let count: Int?

    var body: some View {
        GlassCard(interactive: true) {
            HStack(spacing: Spacing.unit * 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HetzlyColors.accent)
                    .frame(width: 28)

                Text(title)
                    .bodyPrimary()

                Spacer()

                if let count {
                    GlassChip("\(count)")
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textTertiary)
            }
        }
    }
}

// MARK: - Error message / destructive-action helpers

/// Free-function twin of `ResourceListModel.message(for:)` for call sites
/// (delete/action error handling) that aren't going through the list model.
func resourceUserMessage(for error: Error) -> String {
    if let apiError = error as? HetznerAPIError {
        return apiError.userMessage
    }
    return "Something went wrong. Please try again."
}

/// Runs a destructive Cloud API call behind the app's biometric gate, but
/// only when the user has opted into `requireBiometricsForDestructive` in
/// Settings. Returns a human error message on failure (auth or API), `nil`
/// on success.
@MainActor
func confirmDestructive(
    container: AppContainer,
    reason: String,
    action: () async throws -> Void
) async -> String? {
    if container.settings.requireBiometricsForDestructive {
        let approved = await container.biometricGate.authenticate(reason: reason)
        guard approved else {
            return container.biometricGate.lastErrorMessage ?? "Authentication failed. Try again."
        }
    }
    do {
        try await action()
        return nil
    } catch {
        return resourceUserMessage(for: error)
    }
}

// MARK: - Mascot gating for free-function view builders

/// `resourceListBody` is a free function, so it cannot declare an
/// `@Environment` property itself; this tiny wrapper view reads
/// `mascotEnabled` on its own and swaps in a fallback glyph when disabled.
private struct ResourceErrorMascot: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        if container.settings.mascotEnabled {
            MascotView(state: .alarm, scale: 3)
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(HetzlyColors.statusError)
        }
    }
}

/// Auth-error recovery for a `resourceListBody` error banner: an "Update
/// token…" button that opens `UpdateTokenSheet` for the currently scoped
/// project. Reads `ResourcesProjectSelection`/`AppContainer` from the
/// environment (mirroring `ResourceErrorMascot`'s wrapper pattern, since
/// `resourceListBody` is a free function and can't declare `@Environment`
/// itself) rather than threading a project parameter through every
/// `resourceListBody` call site — every caller of `resourceListBody` lives
/// inside `ResourcesHubView`'s `NavigationStack`, which injects
/// `ResourcesProjectSelection` for exactly this purpose. Renders nothing for
/// a non-auth error or when no project is scoped.
private struct ResourceErrorRecovery: View {
    let error: DisplayableError

    @Environment(AppContainer.self) private var container
    @Environment(ResourcesProjectSelection.self) private var selection
    @State private var updateTokenProject: ProjectRecord?

    var body: some View {
        Group {
            if error.isAuthError, let project = scopedProject {
                Button("Update token…") {
                    updateTokenProject = project
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(HetzlyColors.accent)
            }
        }
        .sheet(item: $updateTokenProject) { project in
            UpdateTokenSheet(project: project)
        }
    }

    private var scopedProject: ProjectRecord? {
        guard let projectID = selection.projectID else { return nil }
        return container.projectsStore.projects.first { $0.id == projectID }
    }
}

// MARK: - Shared list scaffold

/// Renders a `ResourceListModel.LoadState` + item array as loading / error /
/// empty / populated `List`, matching the Dashboard/Server Detail
/// stale-while-revalidate presentation conventions. Every Resources list
/// screen (Volumes, Networks, SSH Keys, ...) calls this instead of
/// hand-rolling the same four-way switch.
@MainActor
@ViewBuilder
func resourceListBody<T: Identifiable & Sendable, Row: View>(
    state: ResourceListModel<T>.LoadState,
    items: [T],
    emptyTitle: String,
    emptyMessage: String,
    emptyCTA: String,
    onCreate: @escaping () -> Void,
    onRetry: @escaping () -> Void,
    onRefresh: @escaping @Sendable () async -> Void,
    @ViewBuilder row: @escaping (T) -> Row
) -> some View {
    switch state {
    case .idle, .loading:
        if items.isEmpty {
            ResourceLoadingState()
        } else {
            resourceList(items: items, bannerError: nil, onRefresh: onRefresh, row: row)
        }
    case .failed(let error):
        if items.isEmpty {
            VStack(spacing: Spacing.unit * 4) {
                ResourceErrorMascot()
                Text(error.message)
                    .bodySecondary()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.screenMargin * 2)
                ResourceErrorRecovery(error: error)
                Button("Try Again", action: onRetry)
                    .secondaryCTAStyle()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Spacing.unit * 16)
        } else {
            resourceList(items: items, bannerError: error, onRefresh: onRefresh, row: row)
        }
    case .loaded:
        if items.isEmpty {
            ResourceEmptyState(title: emptyTitle, message: emptyMessage, ctaTitle: emptyCTA, onCreate: onCreate)
        } else {
            resourceList(items: items, bannerError: nil, onRefresh: onRefresh, row: row)
        }
    }
}

@MainActor
@ViewBuilder
private func resourceList<T: Identifiable & Sendable, Row: View>(
    items: [T],
    bannerError: DisplayableError?,
    onRefresh: @escaping @Sendable () async -> Void,
    @ViewBuilder row: @escaping (T) -> Row
) -> some View {
    List {
        if let bannerError {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                ResourceErrorBanner(message: bannerError.message)
                ResourceErrorRecovery(error: bannerError)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        ForEach(items) { item in
            row(item)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(
                    top: Spacing.unit, leading: Spacing.screenMargin,
                    bottom: Spacing.unit, trailing: Spacing.screenMargin
                ))
        }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .refreshable { await onRefresh() }
}

#Preview("Support views") {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 4) {
            ResourceErrorBanner(message: "A network error occurred. Please check your connection and try again.")
            ResourceHubRow(title: "Volumes", systemImage: "externaldrive", count: 3)
            ResourceHubRow(title: "Networks", systemImage: "point.3.connected.trianglepath.dotted", count: nil)
            DetailInfoRow(label: "Size", value: "50 GB")
            DetailInfoRow(label: "Fingerprint", value: ResourceFormatting.truncatedMiddle("SHA256:abcdefghijklmnopqrstuvwxyz0123456789"), monospaced: true)
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

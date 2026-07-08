import HetznerKit
import SwiftUI

/// Validates CIDR blocks entered in the firewall rule editor. Deliberately
/// simple (not a full RFC 4632/5952 implementation) but correct for the
/// inputs Hetzner's firewall API accepts, including the common `0.0.0.0/0`
/// and `::/0` "any" presets.
enum CIDRValidator {
    static func isValid(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slashIndex = trimmed.firstIndex(of: "/") else { return false }
        let address = String(trimmed[trimmed.startIndex..<slashIndex])
        let prefixString = String(trimmed[trimmed.index(after: slashIndex)...])
        guard let prefix = Int(prefixString), !address.isEmpty else { return false }

        if isValidIPv4Address(address) {
            return (0...32).contains(prefix)
        }
        if isValidIPv6Address(address) {
            return (0...128).contains(prefix)
        }
        return false
    }

    private static func isValidIPv4Address(_ address: String) -> Bool {
        let octets = address.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4 else { return false }
        return octets.allSatisfy { octet in
            guard !octet.isEmpty, octet.count <= 3, octet.allSatisfy(\.isNumber), let value = Int(octet) else {
                return false
            }
            if octet.count > 1, octet.first == "0" { return false }
            return (0...255).contains(value)
        }
    }

    /// Permissive but correct IPv6 address check: at most one `::`
    /// compression, up to 8 groups of 1-4 hex digits, and no leading/trailing
    /// stray colons outside a `::`.
    private static func isValidIPv6Address(_ address: String) -> Bool {
        if address == "::" { return true }

        let doubleColonCount = address.components(separatedBy: "::").count - 1
        guard doubleColonCount <= 1 else { return false }
        if address.hasPrefix(":"), !address.hasPrefix("::") { return false }
        if address.hasSuffix(":"), !address.hasSuffix("::") { return false }

        let groups = address
            .components(separatedBy: "::")
            .flatMap { $0.split(separator: ":", omittingEmptySubsequences: true) }
        guard !groups.isEmpty else { return false }
        guard groups.count <= 8 else { return false }
        if doubleColonCount == 0, groups.count != 8 { return false }

        return groups.allSatisfy { group in
            (1...4).contains(group.count) && group.allSatisfy(\.isHexDigit)
        }
    }
}

/// A user-displayable error message, typed so it can travel through
/// `Result` (whose `Failure` must conform to `Error` — `String` doesn't).
struct DisplayError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// Validates the `port` string Hetzner firewall rules accept: a single port
/// ("80") or an inclusive range ("80-85").
enum PortValidator {
    static func isValid(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return false }

        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count, numbers.allSatisfy({ (1...65_535).contains($0) }) else { return false }
        if numbers.count == 2 { return numbers[0] < numbers[1] }
        return true
    }
}

extension FirewallProtocol {
    /// Segmented-control order — excludes `.unknown`, a decode-only fallback
    /// that should never appear as a selectable option when editing a rule.
    static let editableCases: [FirewallProtocol] = [.tcp, .udp, .icmp, .gre, .esp]

    var displayName: String {
        switch self {
        case .tcp: "TCP"
        case .udp: "UDP"
        case .icmp: "ICMP"
        case .gre: "GRE"
        case .esp: "ESP"
        case .unknown: "Unknown"
        }
    }

    /// Protocols without a port concept — port entry is hidden for these.
    var showsPort: Bool {
        switch self {
        case .tcp, .udp: true
        case .icmp, .gre, .esp, .unknown: false
        }
    }

    /// Subtle, color-coded chip tint. Kept within the app's minimal palette
    /// (accent + status colors) rather than introducing new hues.
    var tint: Color {
        switch self {
        case .tcp: HetzlyColors.accent
        case .udp: HetzlyColors.statusRunning
        case .icmp: HetzlyColors.statusTransitioning
        case .gre, .esp: HetzlyColors.textSecondary
        case .unknown: HetzlyColors.textTertiary
        }
    }
}

/// A one-tap starting point for a common rule, offered from the "Templates"
/// menu in `RuleEditSheet`.
struct RuleTemplate: Identifiable {
    let id = UUID()
    let name: String
    let networkProtocol: FirewallProtocol
    let port: String?
    let description: String

    static let all: [RuleTemplate] = [
        RuleTemplate(name: "SSH (22)", networkProtocol: .tcp, port: "22", description: "SSH"),
        RuleTemplate(name: "HTTP (80)", networkProtocol: .tcp, port: "80", description: "HTTP"),
        RuleTemplate(name: "HTTPS (443)", networkProtocol: .tcp, port: "443", description: "HTTPS"),
        RuleTemplate(name: "ICMP ping", networkProtocol: .icmp, port: nil, description: "ICMP ping"),
    ]
}

/// Runs a mutating `CloudClient` call that returns one or more `Action`s and
/// tracks each to completion via `ActionTracker`, collapsing the whole
/// operation into a single success/failure result the view layer can show a
/// saving spinner against.
enum FirewallActionRunner {
    @MainActor
    static func run(client: CloudClient, _ operation: () async throws -> [Action]) async -> Result<Void, HetznerAPIError> {
        do {
            let actions = try await operation()
            let tracker = ActionTracker(client: client)
            for action in actions {
                let result = await track(actionID: action.id, tracker: tracker)
                if case .failure = result { return result }
            }
            return .success(())
        } catch let apiError as HetznerAPIError {
            return .failure(apiError)
        } catch {
            return .failure(.transport(underlying: String(describing: error)))
        }
    }

    @MainActor
    private static func track(actionID: Int, tracker: ActionTracker) async -> Result<Void, HetznerAPIError> {
        for await update in await tracker.track(actionID: actionID) {
            switch update {
            case .finished: return .success(())
            case .failed(let error): return .failure(error)
            case .timedOut: return .failure(.transport(underlying: "This is taking longer than expected. Check back shortly."))
            case .progress: continue
            }
        }
        return .success(())
    }
}

// MARK: - Shared layout/controls (reused by LoadBalancers and DNS — same
// module/target, all three owned by this worker).

/// Wraps its subviews onto multiple rows as needed, left-to-right, top-to-
/// bottom — used for CIDR/value chip lists that shouldn't be clipped or
/// force-scroll horizontally.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? spacing : 0) + size.width
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth)
        return CGSize(width: maxWidth.isFinite ? maxWidth : totalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension View {
    /// Standard row treatment for glass cards hosted inside a `List`: clear
    /// row background (the canvas shows through), no separators, and the
    /// app's screen margins as insets. Lists are used (rather than
    /// `ScrollView`) wherever rows need `.swipeActions`.
    func plainRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Spacing.unit,
                leading: Spacing.screenMargin,
                bottom: Spacing.unit,
                trailing: Spacing.screenMargin
            ))
    }
}

/// A compact glass segmented control for any small, `Equatable` option set —
/// the same visual language as `MetricsRangePicker`, generalized so
/// Firewalls/LoadBalancers/DNS don't each need a bespoke `Picker` (which
/// would require retrofitting `Hashable` onto HetznerKit's wire enums).
struct InlineSegmentedPicker<Option: Equatable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button {
                    withAnimation(.snappy) { selection = option }
                } label: {
                    Text(label(option))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == option ? HetzlyColors.textPrimary : HetzlyColors.textSecondary)
                        .padding(.horizontal, Spacing.unit * 3)
                        .padding(.vertical, Spacing.unit * 1.5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == option {
                                Capsule(style: .continuous).fill(HetzlyColors.accent.opacity(0.9))
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .glassSurface(Capsule(style: .continuous))
    }
}

#Preview("Rule row styling") {
    ZStack {
        CanvasBackground()
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            ForEach(FirewallProtocol.editableCases, id: \.rawValue) { proto in
                HStack {
                    Circle().fill(proto.tint).frame(width: 8, height: 8)
                    Text(proto.displayName).bodySecondary()
                }
            }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}

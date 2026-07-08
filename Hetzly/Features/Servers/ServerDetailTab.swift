import Foundation

/// The two panels Server Detail is split into: everything that acts on the
/// server (`control`) versus the read-only metrics charts (`analytics`).
/// Kept as its own tiny type (rather than inline in `ServerDetailView`) so
/// `ServerDetailTabPicker`'s preview and any future consumer don't need the
/// whole detail view.
enum ServerDetailTab: String, CaseIterable, Identifiable, Sendable {
    case control
    case analytics

    var id: String { rawValue }

    var label: String {
        switch self {
        case .control: "Control"
        case .analytics: "Analytics"
        }
    }
}

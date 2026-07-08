import Foundation

/// The set of power/lifecycle actions available from Server Detail.
///
/// Every case maps 1:1 to a `CloudClient` mutation (see
/// `ServerDetailViewModel.perform(_:on:)`) and carries the plain-language
/// copy shown in the confirmation sheet before it fires.
enum PowerAction: String, CaseIterable, Identifiable, Sendable {
    case powerOn
    case shutdown
    case reboot
    case reset
    case powerOff
    case delete

    var id: String { rawValue }

    /// Short title shown on the action button and confirmation sheet.
    var title: String {
        switch self {
        case .powerOn: "Power On"
        case .shutdown: "Shut Down"
        case .reboot: "Reboot"
        case .reset: "Reset"
        case .powerOff: "Power Off"
        case .delete: "Delete Server"
        }
    }

    /// SF Symbol shown on the circular action button.
    var systemImage: String {
        switch self {
        case .powerOn: "power"
        case .shutdown: "moon"
        case .reboot: "arrow.clockwise"
        case .reset: "bolt"
        case .powerOff: "power.dotted"
        case .delete: "trash"
        }
    }

    /// Destructive actions get warning haptics, the `DestructiveCTA` style,
    /// and (when the user has opted in) a biometric gate before firing.
    var isDestructive: Bool {
        switch self {
        case .reset, .powerOff, .delete: true
        case .powerOn, .shutdown, .reboot: false
        }
    }

    /// Plain-language explanation shown in the confirmation sheet — no
    /// jargon, so a non-technical user understands the real-world effect.
    var confirmSubtitle: String {
        switch self {
        case .powerOn:
            "Powers on the server. This usually takes a few seconds."
        case .shutdown:
            "Sends a graceful shutdown signal, like closing the lid on a laptop. The operating system gets a chance to save its state before powering off."
        case .reboot:
            "Sends a soft restart signal, like restarting from the OS. Running processes get a chance to exit cleanly."
        case .reset:
            "Reset is like pulling the power plug — unsaved data may be lost."
        case .powerOff:
            "Immediately cuts power, like holding down the power button. Unsaved data may be lost."
        case .delete:
            "Permanently destroys this server and everything on its disks. This cannot be undone."
        }
    }

    /// Label on the confirm button in the sheet.
    var confirmButtonTitle: String {
        switch self {
        case .powerOn: "Power On"
        case .shutdown: "Shut Down"
        case .reboot: "Reboot"
        case .reset: "Reset Server"
        case .powerOff: "Power Off"
        case .delete: "Delete Server"
        }
    }

    /// Present-progressive verb used in the active-action progress card,
    /// e.g. "Rebooting… 40%".
    var progressVerb: String {
        switch self {
        case .powerOn: "Powering On"
        case .shutdown: "Shutting Down"
        case .reboot: "Rebooting"
        case .reset: "Resetting"
        case .powerOff: "Powering Off"
        case .delete: "Deleting"
        }
    }
}

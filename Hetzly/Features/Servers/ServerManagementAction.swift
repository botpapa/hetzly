import HetznerKit
import Foundation

/// The set of management actions available from Server Detail beyond the
/// quick power row (`PowerAction`): backups, rescue mode, snapshots, ISO
/// attach/detach, protection, and credential/console actions.
///
/// Every case that reaches the wire maps 1:1 to a `CloudClient` mutation
/// that returns an `Action` (see `ServerDetailViewModel.performManagement`)
/// and is tracked through the same `ActionTracker` plumbing as `PowerAction`.
/// Two things are deliberately **not** modeled here because their
/// `CloudClient` calls don't return a trackable `Action`: renaming
/// (`rename(serverID:name:)`) and label edits (`updateLabels`), both of
/// which are plain `PUT /servers/{id}` calls handled by their own
/// lightweight view-model methods. Rescale (`changeType`) also isn't a case
/// here — it's a multi-step chained flow (optional shutdown → resize →
/// optional power-on) driven by `ServerDetailViewModel.runRescale`.
enum ServerManagementAction: Identifiable, Sendable, Equatable {
    case createSnapshot(description: String)
    case enableBackups
    case disableBackups
    case enableRescue(sshKeyIDs: [Int])
    case disableRescue
    case rebuild(image: Image)
    case attachISO(iso: ISO)
    case detachISO
    case changeProtection(delete: Bool, rebuild: Bool)
    case resetRootPassword
    case requestConsole

    var id: String {
        switch self {
        case .createSnapshot: "createSnapshot"
        case .enableBackups: "enableBackups"
        case .disableBackups: "disableBackups"
        case .enableRescue: "enableRescue"
        case .disableRescue: "disableRescue"
        case .rebuild(let image): "rebuild-\(image.id)"
        case .attachISO(let iso): "attachISO-\(iso.id)"
        case .detachISO: "detachISO"
        case .changeProtection(let delete, let rebuild): "changeProtection-\(delete)-\(rebuild)"
        case .resetRootPassword: "resetRootPassword"
        case .requestConsole: "requestConsole"
        }
    }

    /// Title shown in menus, sheet headers, and confirm sheets.
    var title: String {
        switch self {
        case .createSnapshot: "Create Snapshot"
        case .enableBackups: "Enable Backups"
        case .disableBackups: "Disable Backups"
        case .enableRescue: "Enable Rescue Mode"
        case .disableRescue: "Disable Rescue Mode"
        case .rebuild: "Rebuild Server"
        case .attachISO: "Attach ISO"
        case .detachISO: "Detach ISO"
        case .changeProtection(let delete, _): delete ? "Enable Protection" : "Disable Protection"
        case .resetRootPassword: "Reset Root Password"
        case .requestConsole: "Request Console"
        }
    }

    var systemImage: String {
        switch self {
        case .createSnapshot: "camera"
        case .enableBackups, .disableBackups: "clock.arrow.circlepath"
        case .enableRescue, .disableRescue: "lifepreserver"
        case .rebuild: "arrow.triangle.2.circlepath"
        case .attachISO, .detachISO: "opticaldiscdrive"
        case .changeProtection: "lock.shield"
        case .resetRootPassword: "key"
        case .requestConsole: "terminal"
        }
    }

    /// Whether the confirm sheet uses `DestructiveCTA` styling and warning
    /// haptics. Distinct from `requiresBiometricGate` — some actions are
    /// gated behind biometrics without being visually "destructive" (e.g.
    /// enabling rescue mode doesn't destroy anything, but it's still a
    /// sensitive credential-exposing operation worth a second factor).
    var isDestructive: Bool {
        switch self {
        case .rebuild, .resetRootPassword: true
        default: false
        }
    }

    /// Actions that should re-run the Face ID / Touch ID gate (when the user
    /// has opted into that in Settings) before firing, matching the
    /// CONTRACTS.md-adjacent worker brief's "gated set": rebuild, rescale
    /// (handled separately by `runRescale`), reset password, and rescue
    /// mode enable/disable.
    var requiresBiometricGate: Bool {
        switch self {
        case .rebuild, .resetRootPassword, .enableRescue, .disableRescue: true
        default: false
        }
    }

    /// Plain-language explanation shown in the confirm sheet.
    var confirmSubtitle: String {
        switch self {
        case .createSnapshot:
            "Creates a full disk snapshot you can restore from later. Snapshots are billed like any other image storage."
        case .enableBackups:
            "Takes automatic daily backups on a rolling 7-day window. Adds about 20% to this server's hourly cost."
        case .disableBackups:
            "Stops automatic backups. Existing backups stay until they age out or you delete them."
        case .enableRescue(let sshKeyIDs):
            sshKeyIDs.isEmpty
                ? "Boots a minimal rescue system on the next reboot, with a one-time root password."
                : "Boots a minimal rescue system on the next reboot, using the selected SSH key(s) to log in."
        case .disableRescue:
            "Turns off rescue mode. The server boots normally next time it restarts."
        case .rebuild(let image):
            "Destroys all data on the disk and reinstalls from \(image.description). This cannot be undone."
        case .attachISO(let iso):
            "Mounts \(iso.name ?? iso.description ?? "this ISO") as a virtual disc. The server boots from it on its next restart."
        case .detachISO:
            "Unmounts the attached ISO. The server boots from its normal disk on its next restart."
        case .changeProtection(let delete, _):
            delete
                ? "Blocks Delete and Rebuild for this server until you turn protection off again."
                : "Allows this server to be deleted or rebuilt again."
        case .resetRootPassword:
            "Generates a new one-time root password. Only takes effect immediately if the qemu guest agent is installed and the disk is mounted normally — otherwise it applies on next boot."
        case .requestConsole:
            "Opens a VNC-over-websocket console session for this server."
        }
    }

    var confirmButtonTitle: String {
        switch self {
        case .createSnapshot: "Create Snapshot"
        case .enableBackups: "Enable Backups"
        case .disableBackups: "Disable Backups"
        case .enableRescue: "Enable Rescue Mode"
        case .disableRescue: "Disable Rescue Mode"
        case .rebuild: "Rebuild Server"
        case .attachISO: "Attach ISO"
        case .detachISO: "Detach ISO"
        case .changeProtection(let delete, _): delete ? "Enable Protection" : "Disable Protection"
        case .resetRootPassword: "Reset Password"
        case .requestConsole: "Request Console"
        }
    }

    /// Present-progressive verb for the active-action progress card.
    var progressVerb: String {
        switch self {
        case .createSnapshot: "Creating Snapshot"
        case .enableBackups: "Enabling Backups"
        case .disableBackups: "Disabling Backups"
        case .enableRescue: "Enabling Rescue Mode"
        case .disableRescue: "Disabling Rescue Mode"
        case .rebuild: "Rebuilding"
        case .attachISO: "Attaching ISO"
        case .detachISO: "Detaching ISO"
        case .changeProtection: "Updating Protection"
        case .resetRootPassword: "Resetting Password"
        case .requestConsole: "Requesting Console"
        }
    }

    /// Past-tense copy for the success toast.
    var successText: String {
        switch self {
        case .createSnapshot: "Snapshot created."
        case .enableBackups: "Backups enabled."
        case .disableBackups: "Backups disabled."
        case .enableRescue: "Rescue mode enabled."
        case .disableRescue: "Rescue mode disabled."
        case .rebuild: "Server rebuilt."
        case .attachISO: "ISO attached."
        case .detachISO: "ISO detached."
        case .changeProtection(let delete, _): delete ? "Protection enabled." : "Protection disabled."
        case .resetRootPassword: "Root password reset."
        case .requestConsole: "Console ready."
        }
    }
}

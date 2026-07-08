import Foundation
import Observation

/// User-facing app preferences.
///
/// `@AppStorage` doesn't compose with `@Observable` (it's a SwiftUI
/// property wrapper that only invalidates `View` bodies, not arbitrary
/// `@Observable` reference types), so this reads/writes `UserDefaults`
/// directly and relies on `didSet` to persist changes while `@Observable`
/// handles change tracking for observers.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored
    private let defaults: UserDefaults

    /// Require Face ID / Touch ID (with passcode fallback) before
    /// performing destructive actions (delete server, remove project, etc).
    var requireBiometricsForDestructive: Bool {
        didSet {
            guard requireBiometricsForDestructive != oldValue else { return }
            defaults.set(requireBiometricsForDestructive, forKey: Keys.requireBiometricsForDestructive)
        }
    }

    /// Whether Hetzi (the mascot) is shown throughout the app.
    var mascotEnabled: Bool {
        didSet {
            guard mascotEnabled != oldValue else { return }
            defaults.set(mascotEnabled, forKey: Keys.mascotEnabled)
        }
    }

    /// `"dark"` (always dark) or `"system"` (follow the system appearance).
    var appearance: String {
        didSet {
            guard appearance != oldValue else { return }
            defaults.set(appearance, forKey: Keys.appearance)
        }
    }

    /// Whether the app-switcher privacy shield (blur + cube over content
    /// when the scene isn't active) is enabled. On by default — it keeps
    /// server details and costs out of OS snapshots.
    var privacyShieldEnabled: Bool {
        didSet {
            guard privacyShieldEnabled != oldValue else { return }
            defaults.set(privacyShieldEnabled, forKey: Keys.privacyShieldEnabled)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.requireBiometricsForDestructive =
            (defaults.object(forKey: Keys.requireBiometricsForDestructive) as? Bool) ?? true
        self.mascotEnabled =
            (defaults.object(forKey: Keys.mascotEnabled) as? Bool) ?? true
        self.appearance =
            defaults.string(forKey: Keys.appearance) ?? "dark"
        self.privacyShieldEnabled =
            (defaults.object(forKey: Keys.privacyShieldEnabled) as? Bool) ?? true
    }

    private enum Keys {
        static let requireBiometricsForDestructive = "com.hetzly.settings.requireBiometricsForDestructive"
        static let mascotEnabled = "com.hetzly.settings.mascotEnabled"
        static let appearance = "com.hetzly.settings.appearance"
        static let privacyShieldEnabled = "com.hetzly.settings.privacyShieldEnabled"
    }
}

import AppIntents

/// Registers Hetzly's App Intents with Shortcuts/Siri. Every phrase includes
/// `\(.applicationName)` — App Shortcuts phrases are required to reference
/// the app by name so Siri can disambiguate which app a phrase belongs to;
/// it renders as "Hetzly" from `INFOPLIST_KEY_CFBundleDisplayName`.
struct HetzlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RebootServerIntent(),
            phrases: [
                "Reboot \(\.$server) with \(.applicationName)",
                "Restart \(\.$server) with \(.applicationName)",
            ],
            shortTitle: "Reboot Server",
            systemImageName: "arrow.clockwise.circle"
        )
        AppShortcut(
            intent: ServerStatusIntent(),
            phrases: [
                "\(.applicationName) server status",
                "Check server status in \(.applicationName)",
            ],
            shortTitle: "Server Status",
            systemImageName: "server.rack"
        )
        AppShortcut(
            intent: MonthlyCostIntent(),
            phrases: [
                "What's my \(.applicationName) bill",
                "\(.applicationName) monthly cost",
            ],
            shortTitle: "Monthly Cost",
            systemImageName: "eurosign.circle"
        )
    }
}

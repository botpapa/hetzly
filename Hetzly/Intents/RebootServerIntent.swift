import AppIntents
import HetznerKit

/// "Reboot <server>" — a state-changing action, so it's always
/// confirmation-gated before touching the network. Fires a soft reboot
/// (`CloudClient.reboot(serverID:)`, Hetzner's ACPI-style reboot) and
/// returns as soon as the action is *accepted*, not once it completes —
/// deliberately no `ActionTracker` polling here, to keep the Shortcut/Siri
/// round trip fast. Progress after that point is only visible in the app.
struct RebootServerIntent: AppIntent {
    static let title: LocalizedStringResource = "Reboot Server"
    static let description = IntentDescription("Soft-reboots a Hetzner Cloud server, after confirming.")

    @Parameter(title: "Server")
    var server: ServerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reboot \(\.$server)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(dialog: IntentDialog("Reboot \(server.name)?"))

        let client = try IntentEnvironment.cloudClient(forProjectID: server.projectID)
        do {
            _ = try await client.reboot(serverID: server.serverID)
        } catch let apiError as HetznerAPIError {
            throw HetzlyIntentError.api(apiError.userMessage)
        } catch {
            throw HetzlyIntentError.unreachable
        }

        return .result(dialog: IntentDialog("Rebooting \(server.name)."))
    }
}

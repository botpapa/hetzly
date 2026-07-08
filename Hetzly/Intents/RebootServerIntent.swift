import AppIntents
import HetznerKit

/// "Reboot <server>" — a state-changing action, so it's always
/// confirmation-gated before touching the network. Fires a soft reboot
/// (`CloudClient.reboot(serverID:)`, Hetzner's ACPI-style reboot) and then
/// polls the resulting action with `ActionTracker` for a short window before
/// answering, so the dialog reports what actually happened rather than just
/// "accepted" — a still-`running` action after `POST /reboot` returns 201
/// is not the same thing as the server having actually rebooted, and Siri
/// dialogs claiming success either way would be dishonest either direction.
///
/// AppIntents gives an intent roughly 30s of wall-clock budget end to end
/// (confirmation dialog + both network calls), so polling here is
/// deliberately short — `pollInterval` is tuned so `ActionTracker`'s
/// `60×pollInterval` total-timeout lands around 24s, leaving headroom for
/// the reboot request itself and the confirmation round trip. If the action
/// is still running when that budget runs out, the dialog says so instead
/// of claiming a completion that hasn't happened yet.
struct RebootServerIntent: AppIntent {
    static let title: LocalizedStringResource = "Reboot Server"
    static let description = IntentDescription(
        "Soft-reboots a Hetzner Cloud server, after confirming, and waits briefly to report whether it finished."
    )

    @Parameter(title: "Server")
    var server: ServerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reboot \(\.$server)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await requestConfirmation(dialog: IntentDialog("Reboot \(server.name)?"))

        let client = try IntentEnvironment.cloudClient(forProjectID: server.projectID)
        let action: Action
        do {
            action = try await client.reboot(serverID: server.serverID)
        } catch let apiError as HetznerAPIError {
            throw HetzlyIntentError.api(apiError.userMessage)
        } catch {
            throw HetzlyIntentError.unreachable
        }

        // 60 × 0.4s = 24s total timeout — see the type doc comment above for
        // why this budget is shorter than `ActionTracker`'s 120s production
        // default.
        let tracker = ActionTracker(client: client, pollInterval: 0.4)
        for await update in await tracker.track(actionID: action.id) {
            switch update {
            case .progress:
                continue
            case .finished:
                return .result(dialog: IntentDialog("Rebooted \(server.name)."))
            case .failed(let apiError):
                throw HetzlyIntentError.api(apiError.userMessage)
            case .timedOut:
                return .result(dialog: IntentDialog("Reboot started on \(server.name) — still in progress."))
            }
        }

        // `ActionTracker.track` always yields exactly one terminal update
        // (`.finished`/`.failed`/`.timedOut`) before its stream ends, so
        // every real path returns/throws from inside the loop above — this
        // is unreachable in practice but keeps `perform()` total.
        return .result(dialog: IntentDialog("Reboot started on \(server.name)."))
    }
}

import AppIntents
import HetznerKit

/// "What's my server status?" — a live, read-only lookup. Deliberately
/// simple: status + public IP only, no metrics (CPU/traffic would mean an
/// extra `serverMetrics` round trip Siri's TTS-length dialog has no room for
/// anyway).
struct ServerStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Server Status"
    static let description = IntentDescription(
        "Checks whether a Hetzner Cloud server is running and shows its public IP address."
    )

    @Parameter(title: "Server")
    var server: ServerEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Check status of \(\.$server)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let client = try IntentEnvironment.cloudClient(forProjectID: server.projectID)

        let live: Server
        do {
            live = try await client.server(id: server.serverID)
        } catch let apiError as HetznerAPIError {
            throw HetzlyIntentError.api(apiError.userMessage)
        } catch {
            throw HetzlyIntentError.unreachable
        }

        let ip = live.publicNet.ipv4?.ip ?? live.publicNet.ipv6?.ip ?? "no public IP"
        let summary = "\(live.name) is \(live.status.displayName.lowercased()) — IP \(ip)"

        return .result(value: summary, dialog: IntentDialog(stringLiteral: summary))
    }
}

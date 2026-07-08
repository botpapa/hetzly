import Foundation
import HetznerKit
import Observation

/// Drives `DNSZoneDetailView`: loads the zone's record sets and performs
/// create/update/delete mutations. Record-set endpoints are synchronous
/// (no `Action` to track) — mutations just show a saving flag and reload.
@MainActor
@Observable
final class DNSZoneDetailViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private(set) var zone: DNSZone?
    private(set) var recordSets: [DNSRecordSet] = []
    private(set) var loadState: LoadState = .idle
    private(set) var isSaving = false
    private(set) var actionError: String?

    let projectID: UUID
    let zoneID: Int
    private let container: AppContainer

    init(projectID: UUID, zoneID: Int, container: AppContainer, initial: DNSZone? = nil) {
        self.projectID = projectID
        self.zoneID = zoneID
        self.container = container
        self.zone = initial
    }

    private var client: CloudClient? { container.cloudClient(for: projectID) }

    /// Record sets grouped by type, in a stable, common-first display order.
    var groupedRecordSets: [(type: DNSRecordType, sets: [DNSRecordSet])] {
        let order: [DNSRecordType] = [
            .a, .aaaa, .cname, .mx, .txt, .ns, .srv, .caa, .soa, .ptr, .ds, .hinfo, .https, .rp, .svcb, .tlsa,
            .unknown,
        ]
        let groups = Dictionary(grouping: recordSets, by: \.type)
        return order.compactMap { type in
            guard let sets = groups[type], !sets.isEmpty else { return nil }
            let sorted = sets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            return (type: type, sets: sorted)
        }
    }

    // MARK: - Loading

    func load() async {
        guard let client else {
            loadState = .failed("No stored credentials for this project.")
            return
        }
        if recordSets.isEmpty { loadState = .loading }
        do {
            async let zoneLoad = client.zone(id: zoneID)
            async let recordsLoad = client.listRecordSets(zoneID: zoneID)
            zone = try await zoneLoad
            recordSets = try await recordsLoad
            loadState = .loaded
        } catch {
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Mutations

    func createRecordSet(name: String, type: DNSRecordType, ttl: Int?, values: [String]) async {
        await mutate { client in
            _ = try await client.createRecordSet(
                zoneID: self.zoneID,
                name: name,
                type: type,
                records: values.map { DNSRecordValue(value: $0, comment: nil) },
                ttl: ttl
            )
        }
    }

    func updateRecordSet(name: String, type: DNSRecordType, ttl: Int?, values: [String]) async {
        await mutate { client in
            _ = try await client.updateRecordSet(
                zoneID: self.zoneID,
                name: name,
                type: type,
                records: values.map { DNSRecordValue(value: $0, comment: nil) },
                ttl: ttl
            )
        }
    }

    func deleteRecordSet(_ recordSet: DNSRecordSet) async {
        await mutate { client in
            try await client.deleteRecordSet(zoneID: self.zoneID, name: recordSet.name, type: recordSet.type)
        }
    }

    private func mutate(_ operation: (CloudClient) async throws -> Void) async {
        guard let client, !isSaving else { return }
        actionError = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation(client)
            await load()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    private static func message(for error: Error) -> String {
        (error as? HetznerAPIError)?.userMessage ?? "Something went wrong. Please try again."
    }
}

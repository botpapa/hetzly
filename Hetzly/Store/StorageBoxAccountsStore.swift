import Foundation
import Observation
import SwiftData

/// Thin Keychain helper for Storage Box API tokens, scoped to this store —
/// per `CONTRACTS.md` this lives inside our own files (not `TokenVault`,
/// which is the Cloud/Robot-specific helper owned by other workers) but
/// follows the exact same pattern: a well-known service name, account = the
/// account record's UUID string, `KeychainStore` underneath.
private enum StorageBoxTokenVault {
    static let service = "com.hetzly.storagebox-token"
    private static let store = KeychainStore()

    static func saveToken(_ token: String, accountID: String) throws {
        try store.saveString(token, service: service, account: accountID)
    }

    static func token(accountID: String) throws -> String? {
        try store.readString(service: service, account: accountID)
    }

    static func deleteToken(accountID: String) throws {
        try store.delete(service: service, account: accountID)
    }
}

/// Owns the list of saved Hetzner Storage Box API accounts. Mirrors
/// `RobotAccountsStore`'s shape exactly: every mutation writes through
/// `ModelContext` and (for the token) `StorageBoxTokenVault`, then refetches
/// so `accounts` always reflects what's actually persisted.
@MainActor
@Observable
final class StorageBoxAccountsStore {
    private let context: ModelContext
    private(set) var accounts: [StorageBoxAccountRecord] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Inserts a new Storage Box account record and saves its token to the
    /// keychain. If either half fails, both are rolled back so we never end
    /// up with an account that has no retrievable token, or an orphaned
    /// keychain entry.
    @discardableResult
    func addAccount(label: String, token: String) throws -> StorageBoxAccountRecord {
        let record = StorageBoxAccountRecord(label: label)

        try StorageBoxTokenVault.saveToken(token, accountID: record.id.uuidString)

        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            try? StorageBoxTokenVault.deleteToken(accountID: record.id.uuidString)
            refresh()
            throw error
        }

        refresh()
        return record
    }

    func rename(_ account: StorageBoxAccountRecord, to newLabel: String) {
        account.label = newLabel
        try? context.save()
        refresh()
    }

    /// Deletes the account record and its keychain token.
    func remove(_ account: StorageBoxAccountRecord) throws {
        let accountID = account.id

        context.delete(account)
        try context.save()

        try StorageBoxTokenVault.deleteToken(accountID: accountID.uuidString)

        refresh()
    }

    func token(for account: StorageBoxAccountRecord) throws -> String? {
        try StorageBoxTokenVault.token(accountID: account.id.uuidString)
    }

    private func refresh() {
        let descriptor = FetchDescriptor<StorageBoxAccountRecord>(
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.label),
            ]
        )
        accounts = (try? context.fetch(descriptor)) ?? []
    }
}

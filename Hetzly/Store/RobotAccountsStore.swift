import Foundation
import Observation
import SwiftData

/// Owns the list of saved Hetzner Robot webservice accounts. Mirrors
/// `ProjectsStore`'s shape: every mutation writes through `ModelContext` and
/// (for the password) `TokenVault`, then refetches so `accounts` always
/// reflects what's actually persisted.
@MainActor
@Observable
final class RobotAccountsStore {
    private let context: ModelContext
    private(set) var accounts: [RobotAccountRecord] = []

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    /// Inserts a new Robot account record and saves its password to the
    /// keychain. If either half fails, both are rolled back so we never end
    /// up with an account that has no retrievable password, or an orphaned
    /// keychain entry.
    @discardableResult
    func addAccount(label: String, username: String, password: String) throws -> RobotAccountRecord {
        let record = RobotAccountRecord(label: label, username: username)
        let credentials = TokenVault.RobotCredentials(username: username, password: password)

        try TokenVault.saveRobotCredentials(credentials, accountID: record.id.uuidString)

        context.insert(record)
        do {
            try context.save()
        } catch {
            context.delete(record)
            try? TokenVault.deleteRobotCredentials(accountID: record.id.uuidString)
            refresh()
            throw error
        }

        refresh()
        return record
    }

    func rename(_ account: RobotAccountRecord, to newLabel: String) {
        account.label = newLabel
        try? context.save()
        refresh()
    }

    /// Deletes the account record and its keychain credentials.
    func remove(_ account: RobotAccountRecord) throws {
        let accountID = account.id

        context.delete(account)
        try context.save()

        try TokenVault.deleteRobotCredentials(accountID: accountID.uuidString)

        refresh()
    }

    func credentials(for account: RobotAccountRecord) throws -> TokenVault.RobotCredentials? {
        try TokenVault.robotCredentials(accountID: account.id.uuidString)
    }

    private func refresh() {
        let descriptor = FetchDescriptor<RobotAccountRecord>(
            sortBy: [
                SortDescriptor(\.createdAt),
                SortDescriptor(\.label),
            ]
        )
        accounts = (try? context.fetch(descriptor)) ?? []
    }
}

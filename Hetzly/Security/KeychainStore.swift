import Foundation
import Security

/// Typed errors surfaced by `KeychainStore`. Messages are human-readable and
/// never include the secret material that was being stored, read, or deleted.
enum KeychainError: Error, Sendable, Equatable, LocalizedError {
    case saveFailed(status: OSStatus)
    case readFailed(status: OSStatus)
    case deleteFailed(status: OSStatus)
    case deleteNotVerified
    case unexpectedItemFormat
    case stringEncodingFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Could not save item to the keychain (status \(status))."
        case .readFailed(let status):
            return "Could not read item from the keychain (status \(status))."
        case .deleteFailed(let status):
            return "Could not delete item from the keychain (status \(status))."
        case .deleteNotVerified:
            return "Keychain item deletion could not be verified."
        case .unexpectedItemFormat:
            return "Keychain item was found but was not in the expected format."
        case .stringEncodingFailed:
            return "Could not encode the value as UTF-8 text."
        }
    }
}

/// A minimal, synchronous wrapper over the Keychain Services (`SecItem*`) APIs.
///
/// - Important: Tokens, passwords, and any other credential-bearing material
///   handled by this type must **never** be written to `UserDefaults`,
///   persisted in SwiftData, or emitted to logs (`print`, `os_log`, etc). This
///   type is the single sanctioned place secrets are persisted to disk.
///
/// All items are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
/// (never leaves the device, inaccessible before first unlock after boot) and
/// `kSecAttrSynchronizable = false` (never syncs via iCloud Keychain).
struct KeychainStore: Sendable {
    init() {}

    /// Saves `data` for `(service, account)`, upserting if an item already exists.
    func save(_ data: Data, service: String, account: String) throws {
        var query = baseQuery(service: service, account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = false

        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return
        }
        guard addStatus == errSecDuplicateItem else {
            throw KeychainError.saveFailed(status: addStatus)
        }

        // Item already exists: update its value instead.
        let searchQuery = baseQuery(service: service, account: account)
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, attributesToUpdate as CFDictionary)
        guard updateStatus == errSecSuccess else {
            throw KeychainError.saveFailed(status: updateStatus)
        }
    }

    /// Reads the data stored for `(service, account)`, or `nil` if no item exists.
    func read(service: String, account: String) throws -> Data? {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedItemFormat
            }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.readFailed(status: status)
        }
    }

    /// Deletes the item for `(service, account)` and verifies it is actually gone.
    /// A missing item is treated as a successful delete (idempotent).
    func delete(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status: status)
        }

        // Verify: a subsequent read must return nil.
        if try read(service: service, account: account) != nil {
            throw KeychainError.deleteNotVerified
        }
    }

    // MARK: - String convenience

    /// Saves `string` (UTF-8 encoded) for `(service, account)`.
    func saveString(_ string: String, service: String, account: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.stringEncodingFailed
        }
        try save(data, service: service, account: account)
    }

    /// Reads and UTF-8 decodes the value stored for `(service, account)`.
    func readString(service: String, account: String) throws -> String? {
        guard let data = try read(service: service, account: account) else {
            return nil
        }
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedItemFormat
        }
        return string
    }

    // MARK: - Private

    private func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

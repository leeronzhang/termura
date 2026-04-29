import Foundation
import Security

/// Persists the Mac's Ed25519 signing identity to the macOS Keychain so that
/// `RemoteServer` keeps the same public key across app restarts.
///
/// Without persistence, every `start()` would advertise a different public key,
/// invalidating all previously-paired iPhones and forcing re-pairing on restart.
public actor KeychainDeviceIdentityStore {
    public enum Error: Swift.Error, Equatable {
        case persistenceFailure(code: Int32)
        case decodingFailure
    }

    private let serviceName: String
    private let account: String

    /// Default account is `v2`: PR7 changed the persisted format to
    /// `signingPriv (32B) || kemPriv (32B)` to carry the X25519 KEM
    /// keypair alongside the Ed25519 signing keypair. Old `v1` entries
    /// from before the split are intentionally not read; the user is
    /// pre-release so re-pairing is acceptable.
    public init(serviceName: String, account: String = "device-identity.v2") {
        self.serviceName = serviceName
        self.account = account
    }

    /// Loads the stored identity, or generates and persists a new one on first use.
    public func loadOrCreate() throws -> DeviceIdentity {
        if let existing = try load() {
            return existing
        }
        let fresh = DeviceIdentity.generate()
        try persist(fresh)
        return fresh
    }

    /// Removes the stored identity. Subsequent `loadOrCreate()` will generate a new one.
    /// Used when the user revokes all paired devices and wants to rotate the Mac's key.
    public func reset() throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.persistenceFailure(code: Int32(status))
        }
    }

    private func load() throws -> DeviceIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw Error.persistenceFailure(code: Int32(status))
        }
        guard let data = item as? Data else {
            throw Error.decodingFailure
        }
        return try DeviceIdentity(privateKey: data)
    }

    private func persist(_ identity: DeviceIdentity) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: identity.exportPrivateKeyData(),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributesToUpdate as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw Error.persistenceFailure(code: Int32(updateStatus))
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = identity.exportPrivateKeyData()
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Error.persistenceFailure(code: Int32(addStatus))
        }
    }
}

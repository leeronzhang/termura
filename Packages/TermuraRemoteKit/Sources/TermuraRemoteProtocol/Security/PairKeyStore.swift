import CryptoKit
import Foundation
import Security

/// Persistence surface for the symmetric `PairKey` derived during pairing.
/// Mac harness + iOS app use the protocol so unit tests can inject an
/// in-memory variant without touching the system Keychain.
///
/// `removeAll()` is here for PR9 (disable / revoke-all). PR7 only calls
/// `save` and `key(forPairing:)` — wiring `removeAll` into the user-
/// visible disable flow lands in PR9 and is intentionally not invoked
/// from this layer yet.
public protocol PairKeyStore: Sendable {
    func save(_ key: PairKey) async throws
    func key(forPairing id: UUID) async throws -> PairKey?
    func removeAll() async throws
}

public actor InMemoryPairKeyStore: PairKeyStore {
    private var keys: [UUID: PairKey] = [:]

    public init() {}

    public func save(_ key: PairKey) {
        keys[key.pairingId] = key
    }

    public func key(forPairing id: UUID) -> PairKey? {
        keys[id]
    }

    public func removeAll() {
        keys.removeAll()
    }
}

/// Keychain-backed `PairKeyStore`. Each `PairKey` is stored as a
/// generic password whose `account` is the `pairingId.uuidString`; the
/// raw 32B `SymmetricKey` payload is kSecValueData. Items are stamped
/// `kSecAttrAccessibleAfterFirstUnlock` so the agent can read them in
/// the background after first user unlock.
public actor KeychainPairKeyStore: PairKeyStore {
    public enum Error: Swift.Error, Equatable {
        case persistenceFailure(code: Int32)
        case decodingFailure
    }

    private let serviceName: String

    public init(serviceName: String = "com.termura.remote.pair-key.v2") {
        self.serviceName = serviceName
    }

    public func save(_ key: PairKey) throws {
        let baseQuery = baseQuery(account: key.pairingId.uuidString)
        let payload = key.exportSecretData()
        let updateAttributes: [String: Any] = [
            kSecValueData as String: payload,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw Error.persistenceFailure(code: Int32(updateStatus))
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = payload
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw Error.persistenceFailure(code: Int32(addStatus))
        }
    }

    public func key(forPairing id: UUID) throws -> PairKey? {
        var query = baseQuery(account: id.uuidString)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw Error.persistenceFailure(code: Int32(status))
        }
        guard let data = item as? Data, data.count == 32 else {
            throw Error.decodingFailure
        }
        return PairKey(pairingId: id, secret: SymmetricKey(data: data))
    }

    public func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw Error.persistenceFailure(code: Int32(status))
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
    }
}

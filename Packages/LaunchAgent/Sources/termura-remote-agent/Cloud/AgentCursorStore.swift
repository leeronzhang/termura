// PR8 Phase 2 §6 — persists the cursor `Date` agent uses for
// `gateway.fetch(targetDeviceId:since:)`. Field role: cursor advances
// by `record.createdAt` only; never by `recordName`. `read()` returns
// the historical zero date (`Date(timeIntervalSince1970: 0)`) on
// fresh boot or persistence corruption so the first poll picks up the
// full mailbox backlog.

import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentCursorStore")

actor AgentCursorStore {
    enum CursorError: Error, Sendable, Equatable, LocalizedError {
        case persistenceFailure(code: Int32)

        var errorDescription: String? {
            switch self {
            case let .persistenceFailure(code):
                "Cursor keychain operation failed (OSStatus \(code))."
            }
        }
    }

    private let serviceName: String
    private let account: String
    private var cached: Date?

    init(
        serviceName: String = "com.termura.agent.cursor",
        account: String = "v1"
    ) {
        self.serviceName = serviceName
        self.account = account
    }

    func read() -> Date {
        if let cached { return cached }
        let value: Date
        do {
            value = try loadFromKeychain() ?? Date(timeIntervalSince1970: 0)
        } catch {
            // Keychain read errors fall back to epoch zero so the
            // first poll picks up the entire mailbox; a corrupt
            // cursor entry can't permanently strand records.
            logger.warning("cursor load failed; defaulting to epoch: \(error.localizedDescription)")
            value = Date(timeIntervalSince1970: 0)
        }
        cached = value
        return value
    }

    /// Monotonic advance: a value <= current is silently ignored. The
    /// caller is the dispatcher — only invoked after `gateway.delete`
    /// has succeeded for that record (or the record has been
    /// quarantined and explicitly forced past).
    func advance(to candidate: Date) throws {
        let current = read()
        if candidate <= current { return }
        try persistToKeychain(candidate)
        cached = candidate
    }

    /// PR9 — wipes the persisted cursor and clears the in-memory cache
    /// so the next `read()` returns epoch zero (matching fresh-boot
    /// behaviour). Called by `AgentLifecycle.resetState` from the
    /// resetPairings flow. `errSecItemNotFound` is treated as success
    /// — there's nothing to delete on a fresh agent.
    func reset() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CursorError.persistenceFailure(code: Int32(status))
        }
        cached = nil
    }

    private func loadFromKeychain() throws -> Date? {
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
            throw CursorError.persistenceFailure(code: Int32(status))
        }
        guard let data = item as? Data else { return nil }
        let interval = data.withUnsafeBytes { buf -> TimeInterval in
            guard buf.count == MemoryLayout<TimeInterval>.size else { return 0 }
            return buf.load(as: TimeInterval.self)
        }
        return Date(timeIntervalSince1970: interval)
    }

    private func persistToKeychain(_ date: Date) throws {
        var interval = date.timeIntervalSince1970
        let data = withUnsafeBytes(of: &interval) { Data($0) }
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound {
            throw CursorError.persistenceFailure(code: Int32(updateStatus))
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CursorError.persistenceFailure(code: Int32(addStatus))
        }
    }
}

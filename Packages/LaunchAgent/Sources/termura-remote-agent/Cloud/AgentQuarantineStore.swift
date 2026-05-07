// PR8 Phase 2 §7.3 — persistent retry-state + quarantine list. Two
// states are tracked separately so the runner-side filter only sees
// terminally-quarantined records, never first-attempt blocked ones:
//
//   * `.retrying(attempts:)`  — countable failure has occurred, but
//                               the record is still eligible for
//                               redelivery on the next poll cycle.
//                               `contains(recordName:)` is FALSE so
//                               `AgentCloudKitRunner.pollOnce()` will
//                               re-fetch and re-dispatch this record.
//   * `.quarantined`          — attempts crossed the threshold; the
//                               record is excluded from future polls
//                               and its CloudKit entry is left alone
//                               (operator-visible).
//
// The split fixes a bug from the previous revision where any first-
// attempt failure was treated as "in quarantine" by the runner
// filter, preventing the record from ever reaching the threshold.
//
// Schema is JSON inside a single keychain item. `firstSeenAt` is
// recorded for a future PR9 expiry sweep but not consumed here.

import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentQuarantineStore")

actor AgentQuarantineStore {
    enum QuarantineError: Error, Sendable, Equatable, LocalizedError {
        case persistenceFailure(code: Int32)
        case decodingFailure

        var errorDescription: String? {
            switch self {
            case let .persistenceFailure(code):
                "Quarantine keychain operation failed (OSStatus \(code))."
            case .decodingFailure:
                "Could not decode the quarantine blob from the keychain."
            }
        }
    }

    private let serviceName: String
    private let account: String
    private var entries: [String: QuarantineEntry] = [:]
    private var loaded = false

    init(
        serviceName: String = "com.termura.agent.quarantine",
        account: String = "v1"
    ) {
        self.serviceName = serviceName
        self.account = account
    }

    /// Runner-side filter: returns true ONLY for terminally
    /// quarantined records. Retrying entries (attempts < threshold)
    /// must remain eligible for redelivery so the threshold can be
    /// reached.
    func contains(recordName: String) -> Bool {
        ensureLoaded()
        return entries[recordName]?.state == .quarantined
    }

    func entry(for recordName: String) -> QuarantineEntry? {
        ensureLoaded()
        return entries[recordName]
    }

    func attempts(for recordName: String) -> Int {
        entry(for: recordName)?.attempts ?? 0
    }

    func state(for recordName: String) -> QuarantineState? {
        entry(for: recordName)?.state
    }

    /// Adds or upgrades a quarantine entry. Always lands in the
    /// `.quarantined` state — used by the dispatcher when attempts
    /// cross the threshold. Existing attempts count is preserved.
    func add(_ entry: QuarantineEntry) throws {
        ensureLoaded()
        let toStore = if let existing = entries[entry.recordName] {
            QuarantineEntry(
                recordName: entry.recordName,
                createdAt: existing.createdAt,
                reasonCode: entry.reasonCode,
                attempts: max(existing.attempts, entry.attempts),
                firstSeenAt: existing.firstSeenAt,
                state: .quarantined
            )
        } else {
            QuarantineEntry(
                recordName: entry.recordName,
                createdAt: entry.createdAt,
                reasonCode: entry.reasonCode,
                attempts: entry.attempts,
                firstSeenAt: entry.firstSeenAt,
                state: .quarantined
            )
        }
        entries[entry.recordName] = toStore
        try persist()
    }

    /// Records a countable failure without yet promoting the record
    /// to terminal quarantine. The entry sits in `.retrying` state so
    /// `contains(recordName:)` returns false and the next poll will
    /// re-fetch + re-dispatch it. Returns the new attempts count.
    /// If the entry is already `.quarantined`, attempts are not
    /// incremented (the record won't reach dispatcher again anyway).
    func recordAttempt(
        recordName: String,
        createdAt: Date,
        reasonCode: String,
        now: Date
    ) throws -> Int {
        ensureLoaded()
        if let existing = entries[recordName] {
            if existing.state == .quarantined { return existing.attempts }
            let updated = QuarantineEntry(
                recordName: recordName,
                createdAt: existing.createdAt,
                reasonCode: reasonCode,
                attempts: existing.attempts + 1,
                firstSeenAt: existing.firstSeenAt,
                state: .retrying
            )
            entries[recordName] = updated
            try persist()
            return updated.attempts
        }
        let fresh = QuarantineEntry(
            recordName: recordName,
            createdAt: createdAt,
            reasonCode: reasonCode,
            attempts: 1,
            firstSeenAt: now,
            state: .retrying
        )
        entries[recordName] = fresh
        try persist()
        return fresh.attempts
    }

    func remove(recordName: String) throws {
        ensureLoaded()
        guard entries.removeValue(forKey: recordName) != nil else { return }
        try persist()
    }

    /// PR9 — drops every entry (both `.retrying` and `.quarantined`),
    /// wipes the keychain item, and clears the in-memory dictionary.
    /// Called by `AgentLifecycle.resetState` from the resetPairings
    /// flow. `errSecItemNotFound` is treated as success — the keychain
    /// item is absent on fresh agents and after prior wipes.
    func removeAll() throws {
        ensureLoaded()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw QuarantineError.persistenceFailure(code: Int32(status))
        }
        entries.removeAll()
    }

    func list() -> [QuarantineEntry] {
        ensureLoaded()
        return Array(entries.values).sorted { $0.firstSeenAt < $1.firstSeenAt }
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        do {
            entries = try loadFromKeychain()
        } catch {
            logger.warning("quarantine load failed; starting empty: \(error.localizedDescription)")
            entries = [:]
        }
    }

    private func loadFromKeychain() throws -> [String: QuarantineEntry] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else {
            throw QuarantineError.persistenceFailure(code: Int32(status))
        }
        guard let data = item as? Data else {
            throw QuarantineError.decodingFailure
        }
        let decoded = try JSONDecoder().decode([QuarantineEntry].self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.recordName, $0) })
    }

    private func persist() throws {
        let payload = Array(entries.values)
        let data = try JSONEncoder().encode(payload)
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
            throw QuarantineError.persistenceFailure(code: Int32(updateStatus))
        }
        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw QuarantineError.persistenceFailure(code: Int32(addStatus))
        }
    }
}

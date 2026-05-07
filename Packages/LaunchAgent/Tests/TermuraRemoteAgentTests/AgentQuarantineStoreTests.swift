import Foundation
@testable import termura_remote_agent
import Testing

@Suite("AgentQuarantineStore")
struct AgentQuarantineStoreTests {
    private static func freshServiceName() -> String {
        "com.termura.agent.quarantine.test.\(UUID().uuidString)"
    }

    private static func wipe(serviceName: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test("contains returns false on empty store")
    func emptyContains() async {
        let store = AgentQuarantineStore(serviceName: Self.freshServiceName())
        let hit = await store.contains(recordName: "missing")
        #expect(!hit)
    }

    @Test("recordAttempt sits in .retrying — runner-side filter still treats record as eligible")
    func recordAttemptStartsRetrying() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        let now = Date()
        _ = try await store.recordAttempt(
            recordName: "REC-RETRY",
            createdAt: now,
            reasonCode: "decode_failed",
            now: now
        )
        let visibleToFilter = await store.contains(recordName: "REC-RETRY")
        let state = await store.state(for: "REC-RETRY")
        #expect(!visibleToFilter, "first-attempt blocked records must NOT be filtered out")
        #expect(state == .retrying)
        Self.wipe(serviceName: service)
    }

    @Test("add(.quarantined) flips state — runner filter excludes it")
    func quarantinePromotionMakesContainsTrue() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        let now = Date()
        try await store.add(QuarantineEntry(
            recordName: "REC-Q",
            createdAt: now,
            reasonCode: "decode_failed",
            attempts: 5,
            firstSeenAt: now,
            state: .quarantined
        ))
        let visibleToFilter = await store.contains(recordName: "REC-Q")
        #expect(visibleToFilter)
        #expect(await store.state(for: "REC-Q") == .quarantined)
        Self.wipe(serviceName: service)
    }

    @Test("recordAttempt accumulates and persists")
    func attemptsAccumulate() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        let now = Date()
        let first = try await store.recordAttempt(
            recordName: "REC-1",
            createdAt: now,
            reasonCode: "decode_failed",
            now: now
        )
        let second = try await store.recordAttempt(
            recordName: "REC-1",
            createdAt: now,
            reasonCode: "decode_failed",
            now: now
        )
        #expect(first == 1)
        #expect(second == 2)
        let reloaded = AgentQuarantineStore(serviceName: service)
        #expect(await reloaded.attempts(for: "REC-1") == 2)
        Self.wipe(serviceName: service)
    }

    @Test("add → contains → remove flow")
    func addContainsRemove() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        let entry = QuarantineEntry(
            recordName: "REC-2",
            createdAt: Date(timeIntervalSince1970: 1000),
            reasonCode: "internal_error",
            attempts: 5,
            firstSeenAt: Date(timeIntervalSince1970: 1000),
            state: .quarantined
        )
        try await store.add(entry)
        #expect(await store.contains(recordName: "REC-2"))
        try await store.remove(recordName: "REC-2")
        #expect(await !(store.contains(recordName: "REC-2")))
        Self.wipe(serviceName: service)
    }

    @Test("removeAll clears both .retrying and .quarantined entries and survives reload")
    func removeAllClearsBothStates() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        let now = Date()
        // Mix of states: one retrying, one quarantined.
        _ = try await store.recordAttempt(
            recordName: "REC-RETRY",
            createdAt: now,
            reasonCode: "decode_failed",
            now: now
        )
        try await store.add(QuarantineEntry(
            recordName: "REC-Q",
            createdAt: now,
            reasonCode: "internal_error",
            attempts: 5,
            firstSeenAt: now,
            state: .quarantined
        ))
        // Sanity precondition.
        #expect(await store.state(for: "REC-RETRY") == .retrying)
        #expect(await store.state(for: "REC-Q") == .quarantined)

        try await store.removeAll()

        // In-memory dictionary must be empty.
        #expect(await store.entry(for: "REC-RETRY") == nil)
        #expect(await store.entry(for: "REC-Q") == nil)

        // Keychain must be wiped — a fresh actor over the same service
        // observes no entries.
        let reloaded = AgentQuarantineStore(serviceName: service)
        let reloadedList = await reloaded.list()
        #expect(reloadedList.isEmpty)

        Self.wipe(serviceName: service)
    }

    @Test("removeAll on an empty store is a no-op")
    func removeAllOnEmptyIsNoop() async throws {
        let service = Self.freshServiceName()
        let store = AgentQuarantineStore(serviceName: service)
        try await store.removeAll()
        try await store.removeAll()
        let after = await store.list()
        #expect(after.isEmpty)
        Self.wipe(serviceName: service)
    }
}

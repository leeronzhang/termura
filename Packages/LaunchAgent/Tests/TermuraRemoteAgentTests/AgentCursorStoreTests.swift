import Foundation
@testable import termura_remote_agent
import Testing

@Suite("AgentCursorStore")
struct AgentCursorStoreTests {
    private static func freshKeychainServiceName() -> String {
        "com.termura.agent.cursor.test.\(UUID().uuidString)"
    }

    @Test("read returns epoch zero on first launch")
    func defaultsToEpochZero() async throws {
        let store = AgentCursorStore(serviceName: Self.freshKeychainServiceName())
        let value = await store.read()
        #expect(value == Date(timeIntervalSince1970: 0))
    }

    @Test("advance sets the cursor and survives reload")
    func advancePersists() async throws {
        let serviceName = Self.freshKeychainServiceName()
        let store = AgentCursorStore(serviceName: serviceName)
        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.advance(to: target)
        let reloaded = AgentCursorStore(serviceName: serviceName)
        let value = await reloaded.read()
        #expect(value == target)
        try await wipe(serviceName: serviceName)
    }

    @Test("advance with smaller value is silently ignored")
    func advanceMonotonic() async throws {
        let serviceName = Self.freshKeychainServiceName()
        let store = AgentCursorStore(serviceName: serviceName)
        let later = Date(timeIntervalSince1970: 2_000_000_000)
        try await store.advance(to: later)
        let earlier = Date(timeIntervalSince1970: 1_000_000_000)
        try await store.advance(to: earlier)
        let value = await store.read()
        #expect(value == later)
        try await wipe(serviceName: serviceName)
    }

    @Test("reset wipes keychain and clears in-memory cache so next read is epoch zero")
    func resetClearsBothLayers() async throws {
        let serviceName = Self.freshKeychainServiceName()
        let store = AgentCursorStore(serviceName: serviceName)
        let target = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.advance(to: target)
        // Sanity: store currently holds the advanced value.
        #expect(await store.read() == target)

        try await store.reset()

        // In-memory cache must be cleared.
        #expect(await store.read() == Date(timeIntervalSince1970: 0))

        // Keychain must be cleared too — a fresh actor over the same
        // service name reads epoch zero, not the prior value.
        let reloaded = AgentCursorStore(serviceName: serviceName)
        #expect(await reloaded.read() == Date(timeIntervalSince1970: 0))

        try await wipe(serviceName: serviceName)
    }

    @Test("reset is idempotent — calling on a never-advanced store is a no-op")
    func resetIsIdempotent() async throws {
        let serviceName = Self.freshKeychainServiceName()
        let store = AgentCursorStore(serviceName: serviceName)
        try await store.reset()
        try await store.reset()
        #expect(await store.read() == Date(timeIntervalSince1970: 0))
        try await wipe(serviceName: serviceName)
    }

    private func wipe(serviceName: String) async throws {
        // Keychain cleanup so repeat runs don't leak.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        SecItemDelete(query as CFDictionary)
    }
}

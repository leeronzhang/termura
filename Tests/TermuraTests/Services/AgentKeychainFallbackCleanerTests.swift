import Foundation
import Security
@testable import Termura
import XCTest

/// PR9 Step 6 — exercises `AgentKeychainFallbackCleaner.cleanCursor­
/// AndQuarantine()` against the real keychain. Pre-seeds entries
/// under both fallback service names, runs cleanup, asserts the
/// entries are gone. Both pre/post mutations cover only the two
/// hard-coded service names so the test never collides with the
/// real agent's keychain on the dev machine.
///
/// The cleaner refuses parameterisation (service names are hard-
/// coded constants) so this test deliberately does NOT verify the
/// "delete arbitrary service name" behaviour — that surface doesn't
/// exist by design.
final class AgentKeychainFallbackCleanerTests: XCTestCase {
    private let cursorService = "com.termura.agent.cursor"
    private let quarantineService = "com.termura.agent.quarantine"

    override func setUp() async throws {
        try await super.setUp()
        // Best-effort pre-clean so a previous failed run can't leak
        // entries that this test would mistake as residue.
        wipe(service: cursorService)
        wipe(service: quarantineService)
    }

    override func tearDown() async throws {
        wipe(service: cursorService)
        wipe(service: quarantineService)
        try await super.tearDown()
    }

    func test_cleanCursorAndQuarantine_removesEntriesForBothFallbackServices() async {
        // Seed two real keychain entries under the agent's service names.
        seed(service: cursorService, value: Data([0x01]))
        seed(service: quarantineService, value: Data([0x02]))
        XCTAssertTrue(hasEntry(service: cursorService))
        XCTAssertTrue(hasEntry(service: quarantineService))

        let cleaner = AgentKeychainFallbackCleaner()
        await cleaner.cleanCursorAndQuarantine()

        XCTAssertFalse(hasEntry(service: cursorService),
                       "fallback cleaner must remove the cursor service item")
        XCTAssertFalse(hasEntry(service: quarantineService),
                       "fallback cleaner must remove the quarantine service item")
    }

    func test_cleanCursorAndQuarantine_onEmptyKeychainIsSilentNoop() async {
        // Already wiped in setUp; just call cleaner and assert nothing
        // about the keychain state changed (still empty), no throws.
        let cleaner = AgentKeychainFallbackCleaner()
        await cleaner.cleanCursorAndQuarantine()
        XCTAssertFalse(hasEntry(service: cursorService))
        XCTAssertFalse(hasEntry(service: quarantineService))
    }

    // MARK: - Keychain helpers

    private func seed(service: String, value: Data) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "test",
            kSecValueData as String: value
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private func hasEntry(service: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return status == errSecSuccess
    }

    private func wipe(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

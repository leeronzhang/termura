// PR9 v2.2 §9.4 / §10.1 — fallback only. The primary path for agent
// state reset is `RemoteAgentBridgeLifecycle.resetAgentState` (XPC RPC
// to the agent process). This helper is invoked **exclusively** by
// `RemoteControlController.resetPairings` when (1) the bridge reset
// failed AND (2) `AgentDeathProbe.confirmUnreachable(...)` returned
// `.confirmedDead`. Any other call site is a layering violation —
// the helper crosses the agent's owner boundary by reaching into the
// agent's keychain services from the main app process. That is safe
// only when the agent is verifiably stopped and won't re-write the
// keychain entries from its in-memory cache (see PR9 v2.2 §9.3.3).
//
// Design constraint: the two service names are hard-coded. Refusing
// parameterisation keeps this helper from being repurposed as a
// general-purpose keychain wipe — anything wanting to delete a
// keychain item should reach for the dedicated owner store API
// (`AgentCursorStore.reset()` / `AgentQuarantineStore.removeAll()`)
// via XPC instead.

import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "com.termura.app", category: "AgentKeychainFallbackCleaner")

protocol AgentKeychainFallbackCleaning: Sendable {
    func cleanCursorAndQuarantine() async
}

struct AgentKeychainFallbackCleaner: AgentKeychainFallbackCleaning {
    private let cursorService = "com.termura.agent.cursor"
    private let quarantineService = "com.termura.agent.quarantine"

    init() {}

    /// Best-effort `SecItemDelete` on both agent-side keychain services.
    /// Soft failure: `errSecItemNotFound` is treated as success;
    /// other failures are logged but not propagated. If the user
    /// retries reset, the next attempt will replay the primary path
    /// (XPC RPC) which will overwrite anything we missed.
    func cleanCursorAndQuarantine() async {
        delete(service: cursorService)
        delete(service: quarantineService)
    }

    private func delete(service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.warning(
                "fallback cleaner: SecItemDelete(\(service, privacy: .public)) returned \(status)"
            )
        }
    }
}

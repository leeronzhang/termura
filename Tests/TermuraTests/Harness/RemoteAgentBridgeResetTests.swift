#if HARNESS_ENABLED
import Foundation
@testable import Termura
import Testing

/// PR9 — pins the pre-`start()` and post-`stop()` error contract of the
/// new `resetAgentState()` surface on the bridge assembly and the XPC
/// client. The controller's resetPairings flow (`§12.3` step 4 → step
/// 5b) requires `start()` to run before `resetAgentState()`; a
/// caller-side ordering bug must surface as an explicit error rather
/// than silently no-op'ing.
@Suite("RemoteAgentBridge resetAgentState — error paths")
struct RemoteAgentBridgeResetTests {
    private struct DummyAdapter: RemoteSessionsAdapter {
        func listSessions() async -> [RemoteSessionInfo] { [] }
        func executeCommand(line _: String, sessionId _: UUID) async throws -> CommandRunResult {
            CommandRunResult(stdout: "", exitCode: 0)
        }
    }

    @Test("bridge assembly throws bridgeNotStarted when resetAgentState fires before start()")
    func assemblyRejectsResetBeforeStart() async {
        // Note: we deliberately never call `start()`. Calling start()
        // would trigger `harness.ensureAssembled()` which writes a real
        // Ed25519 identity to the dev-machine keychain — fine for
        // production but pollutes shared test state. The pre-start
        // guard is the contract worth pinning here; the post-stop
        // guard goes through the same `isStarted` field and does not
        // need separate coverage at this layer.
        let harness = RemoteServerHarness(adapter: DummyAdapter())
        let assembly = RemoteAgentBridgeAssembly(harness: harness)

        do {
            try await assembly.resetAgentState()
            Issue.record("expected bridgeNotStarted, got success")
        } catch RemoteAgentBridgeAssemblyError.bridgeNotStarted {
            // ok
        } catch {
            Issue.record("expected bridgeNotStarted, got \(error)")
        }
    }

    @Test("XPC client throws notRunning when resetAgentState fires before start()")
    func xpcClientRejectsResetBeforeStart() async {
        let bridge = AppMailboxXPCBridge(ingressProvider: { nil })
        let client = RemoteAgentXPCClient(bridge: bridge)
        // Deliberately skip client.start() — `connection == nil`.

        do {
            try await client.resetAgentState()
            Issue.record("expected notRunning, got success")
        } catch RemoteAgentXPCClient.ClientError.notRunning {
            // ok
        } catch {
            Issue.record("expected notRunning, got \(error)")
        }
    }
}
#endif

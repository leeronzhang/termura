import Foundation
@testable import termura_remote_agent
import Testing

/// PR9 — exercises the `AgentBridgeXPCBridge.resetAgentState` plumbing
/// in isolation: the reply must arrive **after** the injected onReset
/// closure completes, never before. Pin this here so a future
/// concurrency refactor can't silently turn the reply into a
/// fire-and-forget (which would defeat the controller's β-probe ack
/// dependency).
@Suite("AgentBridgeXPCBridge")
struct AgentBridgeXPCBridgeTests {
    private actor ResetGate {
        private(set) var resetStarted = false
        private(set) var resetFinished = false
        private var resumeContinuation: CheckedContinuation<Void, Never>?

        func markStarted() {
            resetStarted = true
        }

        func markFinished() {
            resetFinished = true
        }

        func waitForRelease() async {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                resumeContinuation = cont
            }
        }

        func release() {
            resumeContinuation?.resume(returning: ())
            resumeContinuation = nil
        }
    }

    @Test("resetAgentState replies only after onReset returns")
    func replyWaitsForReset() async throws {
        let gate = ResetGate()
        let bridge = AgentBridgeXPCBridge(
            onPing: {},
            onStop: {},
            onReset: {
                await gate.markStarted()
                await gate.waitForRelease()
                await gate.markFinished()
            }
        )

        // Use a continuation to detect the moment of reply.
        let replyArrived = Atomic(initial: false)
        let waiter = Task<Void, Never> {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                bridge.resetAgentState { _ in
                    replyArrived.set(true)
                    cont.resume()
                }
            }
        }

        // Wait until onReset has at least started, then assert the
        // reply has NOT yet fired (still blocked inside onReset).
        try await spinUntil(timeout: 1.0) { await gate.resetStarted }
        #expect(replyArrived.get() == false,
                "reply must not fire while onReset is still in flight")

        // Release the gate and let onReset finish; reply should now arrive.
        await gate.release()
        await waiter.value
        #expect(replyArrived.get() == true)
        #expect(await gate.resetFinished == true)
    }

    @Test("pingAgent stays fire-and-forget — replies before any onPing async work")
    func pingAgentRepliesImmediately() async throws {
        // Sanity: confirm the existing fire-and-forget contract for ping
        // is unchanged. This also locks in the asymmetry between ping
        // (sync) and resetAgentState (async-blocking) so a future
        // refactor of one doesn't accidentally swap behaviour.
        let pingCount = Atomic(initial: 0)
        let bridge = AgentBridgeXPCBridge(
            onPing: { pingCount.set(pingCount.get() + 1) },
            onStop: {},
            onReset: {}
        )
        let received = Atomic(initial: false)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            bridge.pingAgent { _ in
                received.set(true)
                cont.resume()
            }
        }
        #expect(received.get())
        #expect(pingCount.get() == 1)
    }

    private func spinUntil(timeout: TimeInterval, predicate: @Sendable @escaping () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await predicate() { return }
            // Task.yield gives the cooperative scheduler a chance to
            // run the in-flight reply task without pinning a wall-clock
            // interval, satisfying the no_task_sleep_in_tests rule.
            await Task.yield()
        }
        Issue.record("timed out waiting for predicate")
    }
}

/// Small thread-safe atomic for cross-task observation in tests. Not
/// production-grade — locks per access — but adequate for synchronising
/// reply observations across `Task` boundaries.
private final class Atomic<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(initial: T) { value = initial }

    func get() -> T {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set(_ newValue: T) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }
}

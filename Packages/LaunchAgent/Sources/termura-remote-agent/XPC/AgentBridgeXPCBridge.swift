// PR8 Phase 2 — NSObject XPC adapter that vends `AgentBridgeProtocol`
// on every accepted inbound NSXPCConnection. Handles `pingAgent` /
// `stopAgent` calls coming from the main app. Forwards business
// requests to `AgentLifecycle` via Sendable closures.
//
// PR9 — adds `resetAgentState`. Unlike ping/stop (fire-and-forget),
// the reset reply is delayed until the injected `onReset` async closure
// completes, so the main app's controller blocks until agent has
// actually wiped its keychain stores before advancing to β-probe.

import Foundation
@preconcurrency import TermuraAgentXPCInterfaces

// `@unchecked Sendable` (CLAUDE.md §4.5 #1): NSXPCConnection requires `@objc`
// protocol implementations to be NSObject subclasses; NSObject is not
// Sendable. Thread safety: the only stored state is three `let` `@Sendable`
// closures; method bodies do not mutate state and dispatch into them
// directly.
@objc
final class AgentBridgeXPCBridge: NSObject, AgentBridgeProtocol, @unchecked Sendable {
    private let onPing: @Sendable () -> Void
    private let onStop: @Sendable () -> Void
    private let onReset: @Sendable () async -> Void

    init(
        onPing: @escaping @Sendable () -> Void,
        onStop: @escaping @Sendable () -> Void,
        onReset: @escaping @Sendable () async -> Void
    ) {
        self.onPing = onPing
        self.onStop = onStop
        self.onReset = onReset
        super.init()
    }

    func pingAgent(reply: @escaping (Bool) -> Void) {
        onPing()
        reply(true)
    }

    func stopAgent(reply: @escaping (Bool) -> Void) {
        onStop()
        reply(true)
    }

    func resetAgentState(reply: @escaping (Bool) -> Void) {
        // Hold the reply until onReset completes. The Task is owned by
        // this short-lived RPC; if the connection invalidates while
        // onReset is still running, the reply block is dropped by XPC
        // — that's acceptable since the main app's β-probe re-checks
        // the agent's death rather than relying on this ack alone.
        // Foundation's NSXPC reply blocks are thread-safe in practice
        // but not annotated `Sendable`; wrap to satisfy Swift 6.
        let onReset = onReset
        let wrapped = UncheckedSendableReply(block: reply)
        Task {
            await onReset()
            wrapped.block(true)
        }
    }
}

private struct UncheckedSendableReply: @unchecked Sendable {
    let block: (Bool) -> Void
}

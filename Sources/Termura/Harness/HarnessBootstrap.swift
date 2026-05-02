import Foundation
import os

/// Wave 1 — public façade for installing the harness integration factory
/// closures. Free build leaves the closures `nil` so callers see the
/// `Null*` fall-backs in `RemoteIntegrationLauncher`. Harness build calls
/// `HarnessIntegrationFactory.install()` exactly once, before
/// `AppDelegate` constructs the first integration, to populate them.
///
/// Why this surface exists:
///   - The pre-Wave-1 design routed `make(adapter:)` and
///     `makeAgentBridge(integration:)` via `#if HARNESS_ENABLED` to
///     a private-impl factory type. That baked the private-impl name
///     into two sites in the public stub.
///   - Closure-based DI collapses those two sites to a single hook
///     installation entry point. The private repo wires installation
///     in its bootstrap (see `runOneTimeInstallIfPossible()` below).
///
/// Concurrency note (CLAUDE.md §4.4):
///   Closure storage cannot use the unsafe-non-isolated escape hatch,
///   so the two factory slots live behind `OSAllocatedUnfairLock<State>`
///   — same pattern as `PtyByteTap`. The setter / getter helpers
///   serialize access on a thread-safe lock without exposing any
///   unsafe-isolation annotation.
@MainActor
enum HarnessBootstrap {
    typealias IntegrationFactory =
        @MainActor @Sendable (any RemoteSessionsAdapter) -> any RemoteIntegration
    typealias AgentBridgeFactory =
        @MainActor @Sendable (any RemoteIntegration) -> any RemoteAgentBridgeLifecycle

    private struct State {
        var integrationFactory: IntegrationFactory?
        var agentBridgeFactory: AgentBridgeFactory?
        var didRun: Bool = false
    }

    private static let state = OSAllocatedUnfairLock<State>(initialState: State())

    /// Wave 1 hook called from `AppDelegate.init`'s very first line.
    /// Idempotent. In Free builds the harness side is absent, so the
    /// `#if HARNESS_ENABLED` branch never compiles in and the closures
    /// stay `nil` — `RemoteIntegrationLauncher.make(_:)` returns the
    /// Null fallback. In harness builds the branch compiles to a single
    /// call into the private install entry, which sets the two closures.
    static func runIfNeeded() {
        let shouldRun = state.withLock { state -> Bool in
            guard !state.didRun else { return false }
            state.didRun = true
            return true
        }
        guard shouldRun else { return }
        runOneTimeInstallIfPossible()
    }

    /// Conditional dispatch into the harness installer. The harness
    /// build provides a real `HarnessIntegrationFactory.install()`; the
    /// Free build leaves this body empty. The single `#if HARNESS_ENABLED`
    /// branch here is the **only** private-impl type-name reference left
    /// in the public stub after Wave 1 — down from two reference sites
    /// (one in each of `make` and `makeAgentBridge`) before.
    @inline(__always)
    private static func runOneTimeInstallIfPossible() {
        #if HARNESS_ENABLED
        HarnessIntegrationFactory.install()
        #endif
    }

    // MARK: - Slot accessors used by HarnessIntegrationFactory.install()

    /// Sets the integration factory closure. Called exactly once on the
    /// main thread inside the harness's `install()` (which runs from
    /// `runIfNeeded()` above, before any `RemoteIntegrationLauncher.make`
    /// caller). Parameter type is spelled out (rather than using
    /// `IntegrationFactory`) so `@escaping` lands at the syntactic
    /// position Swift requires.
    static func setIntegrationFactory(
        _ factory: @escaping @MainActor @Sendable (any RemoteSessionsAdapter) -> any RemoteIntegration
    ) {
        state.withLock { $0.integrationFactory = factory }
    }

    /// Sets the agent-bridge factory closure. Same lifecycle as above.
    static func setAgentBridgeFactory(
        _ factory: @escaping @MainActor @Sendable (any RemoteIntegration) -> any RemoteAgentBridgeLifecycle
    ) {
        state.withLock { $0.agentBridgeFactory = factory }
    }

    /// Read the integration factory closure. Returns `nil` in Free
    /// builds so the launcher falls back to `NullRemoteIntegration`.
    static func currentIntegrationFactory() -> IntegrationFactory? {
        state.withLock(\.integrationFactory)
    }

    /// Read the agent-bridge factory closure. Returns `nil` in Free
    /// builds so the launcher falls back to `NullRemoteAgentBridgeLifecycle`.
    static func currentAgentBridgeFactory() -> AgentBridgeFactory? {
        state.withLock(\.agentBridgeFactory)
    }
}

import Foundation
import os

/// Holds the singleton `AgentEventSource` (Wave 8 / Claude Code transcript
/// watcher). The factory is invoked once via `installAgentEventSource(...)`
/// when the AppDelegate constructs a `LiveRemoteSessionsAdapter`; later
/// reads via `currentAgentEventSource()` return the cached instance.
///
/// Pre-PR3 this enum also stored integration / agent-bridge factory closures
/// for cross-`#if HARNESS_ENABLED` dispatch. PR3 collapsed the open-core
/// boundary; integration / agent-bridge construction now happens directly
/// via `HarnessIntegrationFactory.make(...)` / `.makeAgentBridge(...)`.
@MainActor
enum HarnessBootstrap {
    private static let state = OSAllocatedUnfairLock<(any AgentEventSource)?>(initialState: nil)

    /// Constructs the singleton `AgentEventSource` against the supplied
    /// session-id → cwd resolver. Idempotent — repeat calls keep the first
    /// source so a re-pair / `makeRemoteAdapter` flow does not orphan the
    /// existing file watchers.
    static func installAgentEventSource(
        cwdResolver: @escaping @MainActor @Sendable (UUID) -> String?
    ) {
        let alreadyInstalled = state.withLock { $0 != nil }
        guard !alreadyInstalled else { return }
        let source = LiveAgentEventSource(cwdResolver: cwdResolver)
        state.withLock { $0 = source }
    }

    /// Read the singleton `AgentEventSource` if installed. Returns `nil`
    /// before `installAgentEventSource(...)` runs; callers that depend on
    /// agent events should treat that as "no agent stream available" and
    /// fall back to the PTY stream path.
    static func currentAgentEventSource() -> (any AgentEventSource)? {
        state.withLock { $0 }
    }
}

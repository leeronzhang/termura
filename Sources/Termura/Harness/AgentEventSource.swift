// Wave 8 — agent-conversation event source surface. Public stub
// definitions for the structured `AgentEvent` pipeline that powers
// iOS's `ConversationView`. Live implementation lives in the private
// harness module (paid feature) and is wired through
// `HarnessBootstrap.installAgentEventSource(cwdResolver:)` so the
// public stub never references the private-impl type by name.

import Foundation
import TermuraRemoteProtocol

/// Handle for an agent-event subscription. Mirrors the shape of
/// `PtyByteTap.Subscription` (id + stream) but adds an
/// `AgentEventCheckpoint` so the router can ship a cold-start basis
/// to iOS in one envelope before live events start flowing.
///
/// Owned by the adapter for the lifetime of the subscription; the
/// caller (router) must invoke `unsubscribe(...)` when done so the
/// source can release any file watcher / dispatch source backing
/// the stream.
public struct AgentEventSubscription: Sendable {
    public let id: UUID
    public let checkpoint: AgentEventCheckpoint
    public let stream: AsyncStream<AgentEvent>

    public init(id: UUID, checkpoint: AgentEventCheckpoint, stream: AsyncStream<AgentEvent>) {
        self.id = id
        self.checkpoint = checkpoint
        self.stream = stream
    }
}

/// Wave 8 — agent-conversation event source. Live implementation in
/// the private harness module watches `~/.claude/projects/<encoded-
/// cwd>/<sessionId>.jsonl` files and produces structured events via
/// `ClaudeCodeTranscriptParser`. Free build returns `nil` from
/// `subscribe` so callers degrade to the legacy PTY stream path.
protocol AgentEventSource: Sendable {
    /// Subscribe to a Termura session's agent-event stream. Returns
    /// nil when no transcript can be resolved (Termura PTY not
    /// running Claude Code, no transcript on disk yet).
    func subscribe(sessionId: UUID, sinceEventId: UUID?) async -> AgentEventSubscription?

    /// Cancel a subscription. Idempotent.
    func unsubscribe(sessionId: UUID, subscriptionId: UUID) async
}

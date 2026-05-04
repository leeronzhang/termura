import Foundation

/// 1.3 — structured agent-conversation event for the iOS Remote
/// "ConversationView" path.
///
/// Replaces the PTY byte-stream-as-default model: the Mac side derives
/// these events from the Claude Code transcript JSONL (or, in the
/// future, other CLI agents that publish a structured journal) and
/// pushes them to iOS so the iOS UI renders the conversation with
/// SwiftUI native components (chat bubbles, tool-call cards, etc.)
/// rather than re-implementing a vt terminal.
///
/// Wire shape principles:
/// - The event is **opaque to the wire layer**; the only required
///   metadata is `sessionId` (the Termura session this event belongs
///   to), `eventId` (for since-id resume), `seq` (for ordering /
///   gap detection), and `producedAt` (for UI sorting).
/// - The conversation payload lives in `kind` + `payload`:
///   `kind` discriminates the variant; `payload` is a Codable enum
///   so the iOS renderer can pattern-match without re-parsing.
/// - Backward compatibility: future block types (e.g. citation,
///   web_search) extend `AgentEventPayload` with new cases. Old
///   clients decoding a new payload should fail soft and let the
///   server know via the resume protocol — that path is added
///   alongside the watcher (next phase), not here.

public struct AgentEvent: Sendable, Codable, Equatable, Identifiable {
    /// Stable ID for since-id resume. Carries Claude Code's own
    /// transcript event UUID through the wire so the parser can
    /// dedupe replays without keeping local state.
    public let id: UUID
    public let sessionId: UUID
    /// Monotonic per-session counter, starts at 1 after each fresh
    /// subscribe. Independent from the `id` UUID — used for gap
    /// detection in transit (since-id is the durable cursor for
    /// reconnect).
    public let seq: UInt64
    public let producedAt: Date
    public let payload: AgentEventPayload

    public init(
        id: UUID,
        sessionId: UUID,
        seq: UInt64,
        producedAt: Date,
        payload: AgentEventPayload
    ) {
        self.id = id
        self.sessionId = sessionId
        self.seq = seq
        self.producedAt = producedAt
        self.payload = payload
    }
}

/// Conversation payload variants. MVP renders `userText` and
/// `assistantText`; `assistantToolUse` and `assistantThinking` ship
/// the data so the wire is forward-compatible, but the iOS MVP
/// renderer collapses them into simple "(using Bash)" / "(thinking…)"
/// rows until the rich-card path lands.
public enum AgentEventPayload: Sendable, Codable, Equatable {
    case userText(String)
    case assistantText(String)
    case assistantThinking(String)
    case assistantToolUse(name: String, inputSummary: String)
    case assistantToolResult(summary: String, isError: Bool)

    private enum CodingKeys: String, CodingKey {
        case kind
        case text
        case name
        case inputSummary
        case summary
        case isError
    }

    private enum Kind: String, Codable {
        case userText = "user_text"
        case assistantText = "assistant_text"
        case assistantThinking = "assistant_thinking"
        case assistantToolUse = "assistant_tool_use"
        case assistantToolResult = "assistant_tool_result"
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .userText(text):
            try container.encode(Kind.userText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .assistantText(text):
            try container.encode(Kind.assistantText, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .assistantThinking(text):
            try container.encode(Kind.assistantThinking, forKey: .kind)
            try container.encode(text, forKey: .text)
        case let .assistantToolUse(name, inputSummary):
            try container.encode(Kind.assistantToolUse, forKey: .kind)
            try container.encode(name, forKey: .name)
            try container.encode(inputSummary, forKey: .inputSummary)
        case let .assistantToolResult(summary, isError):
            try container.encode(Kind.assistantToolResult, forKey: .kind)
            try container.encode(summary, forKey: .summary)
            try container.encode(isError, forKey: .isError)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .userText:
            self = try .userText(container.decode(String.self, forKey: .text))
        case .assistantText:
            self = try .assistantText(container.decode(String.self, forKey: .text))
        case .assistantThinking:
            self = try .assistantThinking(container.decode(String.self, forKey: .text))
        case .assistantToolUse:
            self = try .assistantToolUse(
                name: container.decode(String.self, forKey: .name),
                inputSummary: container.decode(String.self, forKey: .inputSummary)
            )
        case .assistantToolResult:
            self = try .assistantToolResult(
                summary: container.decode(String.self, forKey: .summary),
                isError: container.decode(Bool.self, forKey: .isError)
            )
        }
    }
}

/// Client → server: subscribe to a Termura session's agent
/// conversation event stream. `sinceEventId` resumes from a known
/// event (returned by a prior subscribe-success or carried by the
/// last AgentEvent the client persisted) so a background → foreground
/// cycle doesn't lose messages. When `sinceEventId == nil` the server
/// ships a cold-start checkpoint enumerating the most recent N events
/// so the iOS UI has immediate content.
public struct AgentEventSubscribeRequest: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let sinceEventId: UUID?

    public init(sessionId: UUID, sinceEventId: UUID? = nil) {
        self.sessionId = sessionId
        self.sinceEventId = sinceEventId
    }
}

/// Client → server: stop the agent-event stream for a session. Mirror
/// of `PtyStreamUnsubscribeRequest` — `nil` sessionId tears down every
/// agent subscription on the channel (used during disconnect).
public struct AgentEventUnsubscribeRequest: Sendable, Codable, Equatable {
    public let sessionId: UUID?

    public init(sessionId: UUID? = nil) {
        self.sessionId = sessionId
    }
}

/// Server → client: cold-start basis when subscribe succeeds with
/// `sinceEventId == nil` or when the resume cursor falls outside the
/// server's retention window. Carries the most recent `events` so the
/// iOS UI can render history immediately; subsequent live events
/// arrive as `.agentEvent` envelopes.
public struct AgentEventCheckpoint: Sendable, Codable, Equatable {
    public let sessionId: UUID
    public let events: [AgentEvent]
    public let producedAt: Date

    public init(sessionId: UUID, events: [AgentEvent], producedAt: Date) {
        self.sessionId = sessionId
        self.events = events
        self.producedAt = producedAt
    }
}

import Foundation

/// Records a harness-layer event associated with a session.
/// Used for experience codification, rule changes, and milestone tracking.
struct HarnessEvent: Identifiable, Sendable {
    let id: UUID
    let sessionID: SessionID
    let eventType: HarnessEventType
    /// JSON-encoded payload with event-specific data.
    let payload: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        eventType: HarnessEventType,
        payload: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.eventType = eventType
        self.payload = payload
        self.createdAt = createdAt
    }
}

/// Categories of harness events.
enum HarnessEventType: String, Sendable, Codable, CaseIterable {
    /// A rule was appended to a harness file (e.g. AGENTS.md).
    case ruleAppend
    /// An error was captured for potential rule codification.
    case error
    /// A token milestone was reached (e.g. 50%, 80% of context window).
    case tokenMilestone
    /// Agent session ended, handoff context generated.
    case sessionHandoff
}

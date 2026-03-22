import Foundation

/// Represents a single message within a session's conversation history.
/// Follows the dual-track protocol: `contentType` separates model-visible
/// messages from metadata and UI-only entries.
struct SessionMessage: Identifiable, Sendable {
    let id: SessionMessageID
    let sessionID: SessionID
    let role: MessageRole
    let contentType: MessageContentType
    let content: String
    let tokenCount: Int
    let createdAt: Date

    init(
        id: SessionMessageID = SessionMessageID(),
        sessionID: SessionID,
        role: MessageRole,
        contentType: MessageContentType,
        content: String,
        tokenCount: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.role = role
        self.contentType = contentType
        self.content = content
        self.tokenCount = tokenCount
        self.createdAt = createdAt
    }
}

// MARK: - Role

/// Who produced the message.
enum MessageRole: String, Sendable, Codable, CaseIterable {
    case user
    case assistant
    case system
}

// MARK: - Content Type (dual-track)

/// Determines which track a message belongs to.
/// - `model`: sent to the LLM as part of context.
/// - `metadata`: persisted but never sent to the LLM (harness state, token stats).
/// - `ui`: used only for UI rendering (chunk card data, styling hints).
enum MessageContentType: String, Sendable, Codable, CaseIterable {
    case model
    case metadata
    // swiftlint:disable:next identifier_name
    case ui
}

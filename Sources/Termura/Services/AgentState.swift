import Foundation

/// Identifies the type of AI coding agent running in a terminal session.
enum AgentType: String, Sendable, Codable, CaseIterable {
    case claudeCode
    case codex
    case aider
    case openCode
    case pi
    case unknown
}

/// Current operational status of a detected agent.
enum AgentStatus: String, Sendable, Codable, CaseIterable {
    /// Agent is idle, waiting at its own prompt.
    case idle
    /// Agent is processing / generating a response.
    case thinking
    /// Agent is executing a tool (file write, shell command, etc.).
    case toolRunning
    /// Agent is waiting for user confirmation or input.
    case waitingInput
    /// Agent encountered an error.
    case error
    /// Agent task completed.
    case completed
}

/// Snapshot of a detected agent's state within a session.
struct AgentState: Identifiable, Sendable {
    let id: UUID
    let sessionID: SessionID
    let agentType: AgentType
    var status: AgentStatus
    var currentTask: String?
    var tokenCount: Int
    let startedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        agentType: AgentType,
        status: AgentStatus = .idle,
        currentTask: String? = nil,
        tokenCount: Int = 0,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentType = agentType
        self.status = status
        self.currentTask = currentTask
        self.tokenCount = tokenCount
        self.startedAt = startedAt
    }

    /// Whether this agent needs user attention (input or error).
    var needsAttention: Bool {
        status == .waitingInput || status == .error
    }
}

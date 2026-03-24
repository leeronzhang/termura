import Foundation

/// Identifies the type of AI coding agent running in a terminal session.
enum AgentType: String, Sendable, Codable, CaseIterable {
    case claudeCode
    case codex
    case aider
    case openCode
    case pi
    case unknown

    /// Default context window token limit for this agent type.
    var contextWindowLimit: Int {
        switch self {
        case .claudeCode: AppConfig.ContextWindow.claudeCodeLimit
        case .codex: AppConfig.ContextWindow.codexLimit
        case .aider: AppConfig.ContextWindow.aiderLimit
        case .openCode: AppConfig.ContextWindow.openCodeLimit
        case .pi: AppConfig.ContextWindow.piLimit
        case .unknown: AppConfig.ContextWindow.unknownLimit
        }
    }
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
    /// Context window token limit for the detected agent.
    var contextWindowLimit: Int
    let startedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        agentType: AgentType,
        status: AgentStatus = .idle,
        currentTask: String? = nil,
        tokenCount: Int = 0,
        contextWindowLimit: Int? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentType = agentType
        self.status = status
        self.currentTask = currentTask
        self.tokenCount = tokenCount
        self.contextWindowLimit = contextWindowLimit ?? agentType.contextWindowLimit
        self.startedAt = startedAt
    }

    /// Whether this agent needs user attention (input or error).
    var needsAttention: Bool {
        status == .waitingInput || status == .error
    }

    /// Context usage as a fraction of the context window (0.0–1.0).
    var contextUsageFraction: Double {
        guard contextWindowLimit > 0 else { return 0 }
        return min(Double(tokenCount) / Double(contextWindowLimit), 1.0)
    }

    /// True when context usage exceeds the warning threshold.
    var isContextWarning: Bool {
        contextUsageFraction >= AppConfig.ContextWindow.warningThreshold
    }

    /// True when context usage exceeds the critical threshold.
    var isContextCritical: Bool {
        contextUsageFraction >= AppConfig.ContextWindow.criticalThreshold
    }
}

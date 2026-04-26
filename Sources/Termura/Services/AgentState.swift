import Foundation

/// Identifies the type of AI coding agent running in a terminal session.
enum AgentType: String, Sendable, Codable, CaseIterable {
    case claudeCode
    case codex
    case aider
    case openCode
    case gemini
    case pi
    case unknown

    /// Human-readable display name for sidebar and tab titles.
    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "OpenAI Codex"
        case .aider: "Aider"
        case .openCode: "OpenCode"
        case .gemini: "Gemini CLI"
        case .pi: "Pi"
        case .unknown: "Terminal"
        }
    }

    /// Default context window token limit for this agent type.
    var contextWindowLimit: Int {
        switch self {
        case .claudeCode: AppConfig.ContextWindow.claudeCodeLimit
        case .codex: AppConfig.ContextWindow.codexLimit
        case .aider: AppConfig.ContextWindow.aiderLimit
        case .openCode: AppConfig.ContextWindow.openCodeLimit
        case .gemini: AppConfig.ContextWindow.geminiLimit
        case .pi: AppConfig.ContextWindow.piLimit
        case .unknown: AppConfig.ContextWindow.unknownLimit
        }
    }

    /// Shell command used to launch this agent in a fresh terminal session.
    /// Empty for `.unknown`; callers must guard against an empty result.
    var defaultLaunchCommand: String {
        switch self {
        case .claudeCode: "claude"
        case .codex: "codex"
        case .aider: "aider"
        case .openCode: "opencode"
        case .gemini: "gemini"
        case .pi: "pi"
        case .unknown: ""
        }
    }

    /// Shell command used to resume a previous session of this agent.
    /// Falls back to `defaultLaunchCommand` for agents without a dedicated resume flag.
    /// Claude Code uses `--continue` to resume the last conversation.
    var resumeCommand: String {
        switch self {
        case .claudeCode: "claude --continue"
        default: defaultLaunchCommand
        }
    }

    /// Arguments for a non-interactive one-shot invocation that prints a single response and exits.
    /// Used by the AI commit flow to delegate work to the user's CLI agent without occupying
    /// any interactive session. Returns nil for agents whose headless mode is not yet validated.
    func headlessArgs(prompt: String) -> [String]? {
        switch self {
        case .claudeCode: ["-p", prompt]
        case .codex: ["exec", prompt]
        case .aider, .openCode, .gemini, .pi, .unknown: nil
        }
    }

    /// True when `headlessArgs(prompt:)` returns a non-nil invocation for this agent.
    var supportsHeadless: Bool {
        headlessArgs(prompt: "") != nil
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

/// Token statistics parsed from agent output (e.g. Claude Code cost summary).
struct ParsedTokenStats: Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedTokens: Int?
    var totalCost: Double?
}

/// Snapshot of a detected agent's state within a session.
struct AgentState: Identifiable, Sendable {
    let id: UUID
    let sessionID: SessionID
    let agentType: AgentType
    var status: AgentStatus
    var currentTask: String?
    var tokenCount: Int
    /// Token breakdown by category.
    var inputTokens: Int
    var outputTokens: Int
    var cachedTokens: Int
    /// Estimated cost in USD parsed from agent output.
    var estimatedCostUSD: Double
    /// Context window token limit for the detected agent.
    var contextWindowLimit: Int
    /// File path currently being written/edited by the agent, if detectable.
    var activeFilePath: String?
    let startedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        agentType: AgentType,
        status: AgentStatus = .idle,
        currentTask: String? = nil,
        tokenCount: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cachedTokens: Int = 0,
        estimatedCostUSD: Double = 0,
        contextWindowLimit: Int? = nil,
        activeFilePath: String? = nil,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.sessionID = sessionID
        self.agentType = agentType
        self.status = status
        self.currentTask = currentTask
        self.tokenCount = tokenCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.contextWindowLimit = contextWindowLimit ?? agentType.contextWindowLimit
        self.activeFilePath = activeFilePath
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

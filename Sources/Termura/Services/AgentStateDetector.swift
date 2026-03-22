import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Detects AI agent type and operational status from PTY output.
/// Uses startup command matching and ongoing output pattern analysis.
actor AgentStateDetector {

    private var detectedType: AgentType?
    private var currentStatus: AgentStatus = .idle
    private let sessionID: SessionID

    init(sessionID: SessionID) {
        self.sessionID = sessionID
    }

    // MARK: - Command Detection

    /// Analyze a command string to detect agent launch.
    func detectFromCommand(_ command: String) -> AgentType? {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for (pattern, type) in Self.launchPatterns {
            if cmd.hasPrefix(pattern) || cmd.contains("/\(pattern)") {
                detectedType = type
                currentStatus = .idle
                logger.info("Detected agent \(type.rawValue) in session \(self.sessionID)")
                return type
            }
        }
        return nil
    }

    // MARK: - Output Analysis

    /// Analyze a batch of terminal output to update agent status.
    func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return .idle }

        let sample = String(text.suffix(2000))

        if isWaitingInput(sample) {
            currentStatus = .waitingInput
        } else if isError(sample) {
            currentStatus = .error
        } else if isToolRunning(sample) {
            currentStatus = .toolRunning
        } else if isThinking(sample) {
            currentStatus = .thinking
        } else if isCompleted(sample) {
            currentStatus = .completed
        }

        return currentStatus
    }

    /// Build a full AgentState snapshot.
    func buildState(tokenCount: Int = 0) -> AgentState? {
        guard let type = detectedType else { return nil }
        return AgentState(
            sessionID: sessionID,
            agentType: type,
            status: currentStatus,
            tokenCount: tokenCount
        )
    }

    /// Reset detection state.
    func reset() {
        detectedType = nil
        currentStatus = .idle
    }

    // MARK: - Pattern Matching

    private static let launchPatterns: [(String, AgentType)] = [
        ("claude", .claudeCode),
        ("codex", .codex),
        ("aider", .aider),
        ("opencode", .openCode),
        ("oc ", .openCode),
        ("pi ", .pi),
        ("pi-agent", .pi)
    ]

    private func isWaitingInput(_ text: String) -> Bool {
        // Claude Code ">" prompt, Codex confirm, Aider ">"
        text.hasSuffix("> ") || text.hasSuffix(">\n")
            || text.contains("[Y/n]") || text.contains("[y/N]")
            || text.contains("Do you want to proceed")
            || text.contains("permission")
    }

    private func isError(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("error:") || lowered.contains("fatal:")
            || lowered.contains("panic:") || lowered.contains("traceback")
            || lowered.contains("api error") || lowered.contains("rate limit")
    }

    private func isToolRunning(_ text: String) -> Bool {
        text.contains("⏺") || text.contains("Running:")
            || text.contains("Executing:") || text.contains("Writing to")
            || text.contains("tool_use") || text.contains("bash(")
    }

    private func isThinking(_ text: String) -> Bool {
        text.contains("Thinking") || text.contains("…")
            || text.contains("Generating") || text.contains("⠋")
            || text.contains("⠙") || text.contains("⠹")
    }

    private func isCompleted(_ text: String) -> Bool {
        text.contains("Task completed") || text.contains("Done!")
            || text.contains("finished") || text.contains("✓")
    }
}

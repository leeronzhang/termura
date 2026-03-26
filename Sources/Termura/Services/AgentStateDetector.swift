import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Precompiled regex patterns for parsing token stats from agent output.
private enum TokenStatRegex {
    static let cost: NSRegularExpression? = compile("Total cost:\\s*\\$([\\d.]+)")
    static let input: NSRegularExpression? = compile("Input:\\s*([\\d,.]+)k?")
    static let output: NSRegularExpression? = compile("Output:\\s*([\\d,.]+)k?")
    static let cache: NSRegularExpression? = compile("Cache read:\\s*([\\d,.]+)k?")

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            logger.error("Failed to compile regex '\(pattern)': \(error)")
            return nil
        }
    }
}

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

        let sample = String(text.suffix(AppConfig.Agent.outputAnalysisSuffixLength))

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

    // MARK: - Token Stats Parsing

    /// Parse token usage and cost from agent output text.
    /// Returns nil if no recognizable token stats are found.
    func parseTokenStats(_ text: String) -> ParsedTokenStats? {
        var stats = ParsedTokenStats()
        var found = false

        if let cost = Self.extractDouble(from: text, pattern: Self.costPattern) {
            stats.totalCost = cost
            found = true
        }
        if let input = Self.extractTokenCount(from: text, pattern: Self.inputPattern) {
            stats.inputTokens = input
            found = true
        }
        if let output = Self.extractTokenCount(from: text, pattern: Self.outputPattern) {
            stats.outputTokens = output
            found = true
        }
        if let cached = Self.extractTokenCount(from: text, pattern: Self.cachePattern) {
            stats.cachedTokens = cached
            found = true
        }

        return found ? stats : nil
    }

    /// Reset detection state.
    func reset() {
        detectedType = nil
        currentStatus = .idle
    }

    // MARK: - Token Stat Patterns

    private nonisolated static let costPattern = TokenStatRegex.cost
    private nonisolated static let inputPattern = TokenStatRegex.input
    private nonisolated static let outputPattern = TokenStatRegex.output
    private nonisolated static let cachePattern = TokenStatRegex.cache

    private static func extractDouble(
        from text: String,
        pattern: NSRegularExpression?
    ) -> Double? {
        guard let regex = pattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[captureRange].replacingOccurrences(of: ",", with: ""))
    }

    private static func extractTokenCount(
        from text: String,
        pattern: NSRegularExpression?
    ) -> Int? {
        guard let value = extractDouble(from: text, pattern: pattern) else { return nil }
        // If the matched text ends with 'k', the value is in thousands
        guard let regex = pattern else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let fullRange = Range(match.range, in: text) else { return nil }
        let matched = String(text[fullRange])
        if matched.lowercased().hasSuffix("k") {
            return Int(value * 1000)
        }
        return Int(value)
    }

    // MARK: - Pattern Matching

    private static let launchPatterns: [(String, AgentType)] = [
        ("claude", .claudeCode),
        ("codex", .codex),
        ("aider", .aider),
        ("opencode", .openCode),
        ("oc ", .openCode),
        ("gemini", .gemini),
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
        text.contains("\u{23FA}") || text.contains("Running:")
            || text.contains("Executing:") || text.contains("Writing to")
            || text.contains("tool_use") || text.contains("bash(")
    }

    private func isThinking(_ text: String) -> Bool {
        text.contains("Thinking") || text.contains("\u{2026}")
            || text.contains("Generating") || text.contains("\u{280B}")
            || text.contains("\u{2819}") || text.contains("\u{2839}")
    }

    private func isCompleted(_ text: String) -> Bool {
        text.contains("Task completed") || text.contains("Done!")
            || text.contains("finished") || text.contains("\u{2713}")
    }
}

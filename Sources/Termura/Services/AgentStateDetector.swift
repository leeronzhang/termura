import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Precompiled regex patterns for parsing token stats from agent output.
/// Uses non-optional types — the hard-coded patterns are guaranteed well-formed.
/// A compilation failure here would indicate a system-level issue, so we trap immediately
/// rather than silently degrading all token parsing for the lifetime of the process.
private enum TokenStatRegex {
    static let cost = compile("Total cost:\\s*\\$([\\d.]+)")
    static let input = compile("Input:\\s*([\\d,.]+)k?")
    static let output = compile("Output:\\s*([\\d,.]+)k?")
    static let cache = compile("Cache read:\\s*([\\d,.]+)k?")

    private static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            // These are hard-coded, well-formed patterns. If compilation fails,
            // the process is in a broken state (e.g., ICU library missing).
            preconditionFailure("Failed to compile static regex '\(pattern)': \(error)")
        }
    }
}

/// Detects AI agent type and operational status from PTY output.
/// Uses startup command matching and ongoing output pattern analysis.
actor AgentStateDetector {
    private var detectedType: AgentType?
    private var currentStatus: AgentStatus = .idle
    private var detectedAt: Date?
    private var lastStatusChange: Date?
    private var parsedCost: Double = 0
    private let sessionID: SessionID

    /// Valid state transitions — prevents impossible jumps
    /// (e.g. idle -> completed without going through thinking first).
    private static let validTransitions: [AgentStatus: Set<AgentStatus>] = [
        .idle: [.thinking, .toolRunning, .waitingInput, .error],
        .thinking: [.toolRunning, .waitingInput, .completed, .error, .idle],
        .toolRunning: [.thinking, .waitingInput, .completed, .error, .idle],
        .waitingInput: [.thinking, .toolRunning, .idle, .error],
        .completed: [.idle, .thinking, .toolRunning],
        .error: [.idle, .thinking, .toolRunning, .waitingInput]
    ]

    init(sessionID: SessionID) {
        self.sessionID = sessionID
    }

    // MARK: - Command Detection

    /// Analyze a command string to detect agent launch.
    func detectFromCommand(_ command: String) -> AgentType? {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sid = sessionID
        for (pattern, type) in Self.launchPatterns {
            if cmd.hasPrefix(pattern) || cmd.contains("/\(pattern)") {
                detectedType = type
                currentStatus = .idle
                detectedAt = Date()
                logger.info("Detected agent \(type.rawValue) in session \(sid)")
                return type
            }
        }
        return nil
    }

    /// Update the accumulated cost from parsed agent output.
    func updateCost(_ cost: Double) {
        parsedCost = cost
    }

    /// Set or update the detected agent type (used when detection happens outside the detector).
    func setDetectedType(_ type: AgentType) {
        let sid = sessionID
        detectedType = type
        currentStatus = .idle
        detectedAt = Date()
        parsedCost = 0
        logger.info("Agent \(type.rawValue) set externally in session \(sid)")
    }

    // MARK: - Output Analysis

    /// Analyze a batch of terminal output to update agent status.
    /// Evaluates the status rule table top-to-bottom; first match wins.
    /// Applies cooldown and state-transition constraints to suppress false positives.
    func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return .idle }

        let sample = String(text.suffix(AppConfig.Agent.outputAnalysisSuffixLength))

        guard let matched = evaluateRules(sample),
              matched != currentStatus else {
            return currentStatus
        }

        // Enforce valid state transitions.
        guard Self.validTransitions[currentStatus]?.contains(matched) ?? false else {
            return currentStatus
        }

        // Enforce cooldown between transitions to avoid flip-flopping on noisy output.
        let now = Date()
        if let last = lastStatusChange,
           now.timeIntervalSince(last) < AppConfig.Agent.statusChangeCooldown {
            return currentStatus
        }

        currentStatus = matched
        lastStatusChange = now
        return currentStatus
    }

    /// Build a full AgentState snapshot.
    func buildState(tokenCount: Int = 0) -> AgentState? {
        guard let type = detectedType else { return nil }
        return AgentState(
            sessionID: sessionID,
            agentType: type,
            status: currentStatus,
            tokenCount: tokenCount,
            estimatedCostUSD: parsedCost,
            startedAt: detectedAt ?? Date()
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
        detectedAt = nil
        lastStatusChange = nil
    }

    // MARK: - Token Stat Patterns

    private nonisolated static let costPattern = TokenStatRegex.cost
    private nonisolated static let inputPattern = TokenStatRegex.input
    private nonisolated static let outputPattern = TokenStatRegex.output
    private nonisolated static let cachePattern = TokenStatRegex.cache

    private static func extractDouble(
        from text: String,
        pattern: NSRegularExpression
    ) -> Double? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[captureRange].replacingOccurrences(of: ",", with: ""))
    }

    private static func extractTokenCount(
        from text: String,
        pattern: NSRegularExpression
    ) -> Int? {
        guard let value = extractDouble(from: text, pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
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

    /// Ordered rule table for status detection. Evaluated top-to-bottom;
    /// first match wins. Higher-priority statuses appear earlier.
    /// Each rule is independently testable via `StatusRule.matches(_:)`.
    static let statusRules: [StatusRule] = [
        // -- waitingInput: highest priority (user action required) --
        StatusRule(.waitingInput, .suffix("> "), label: "prompt-suffix"),
        StatusRule(.waitingInput, .suffix(">\n"), label: "prompt-suffix-nl"),
        StatusRule(.waitingInput, .contains("[Y/n]"), label: "confirm-yn"),
        StatusRule(.waitingInput, .contains("[y/N]"), label: "confirm-yN"),
        StatusRule(.waitingInput, .contains("Do you want to proceed"), label: "proceed-prompt"),
        StatusRule(.waitingInput, .contains("permission to"), label: "permission-prompt"),

        // -- error: second priority (needs attention) --
        StatusRule(.error, .containsCaseInsensitive("api error"), label: "api-error"),
        StatusRule(.error, .containsCaseInsensitive("rate limit"), label: "rate-limit"),
        StatusRule(.error, .containsCaseInsensitive("fatal:"), label: "fatal"),
        StatusRule(.error, .containsCaseInsensitive("panic:"), label: "panic"),
        StatusRule(.error, .containsCaseInsensitive("traceback"), label: "traceback"),
        StatusRule(.error, .containsCaseInsensitive("error:"), label: "error-colon"),

        // -- toolRunning: agent is executing a tool --
        StatusRule(.toolRunning, .contains("\u{23FA}"), label: "record-icon"),
        StatusRule(.toolRunning, .contains("Running:"), label: "running-label"),
        StatusRule(.toolRunning, .contains("Executing:"), label: "executing-label"),
        StatusRule(.toolRunning, .contains("Writing to"), label: "writing-to"),
        StatusRule(.toolRunning, .contains("tool_use"), label: "tool-use-tag"),
        StatusRule(.toolRunning, .contains("bash("), label: "bash-call"),

        // -- thinking: agent is generating --
        StatusRule(.thinking, .contains("Thinking"), label: "thinking-word"),
        // Removed ellipsis (\u{2026}) — too many false positives from npm/build output.
        StatusRule(.thinking, .contains("Generating"), label: "generating-word"),
        StatusRule(.thinking, .contains("\u{280B}"), label: "braille-spinner-1"),
        StatusRule(.thinking, .contains("\u{2819}"), label: "braille-spinner-2"),
        StatusRule(.thinking, .contains("\u{2839}"), label: "braille-spinner-3"),

        // -- completed: lowest priority --
        StatusRule(.completed, .contains("Task completed"), label: "task-completed"),
        StatusRule(.completed, .contains("Done!"), label: "done-bang"),
        StatusRule(.completed, .contains("finished"), label: "finished-word"),
        StatusRule(.completed, .contains("\u{2713}"), label: "checkmark")
    ]

    /// Evaluates status rules against a text sample.
    /// Returns the status of the first matching rule, or nil if no rule matches.
    private func evaluateRules(_ text: String) -> AgentStatus? {
        for rule in Self.statusRules where rule.matches(text) {
            return rule.status
        }
        return nil
    }
}

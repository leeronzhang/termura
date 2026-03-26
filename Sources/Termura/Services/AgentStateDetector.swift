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
            // Non-critical: static regex — the hard-coded patterns are well-formed.
            // If compilation fails here it indicates a system-level issue, not a code defect.
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
    private var detectedAt: Date?
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
                detectedAt = Date()
                logger.info("Detected agent \(type.rawValue) in session \(self.sessionID)")
                return type
            }
        }
        return nil
    }

    /// Directly set the detected agent type (used when detection happens outside the detector).
    func setDetectedType(_ type: AgentType) {
        guard detectedType == nil else { return }
        detectedType = type
        currentStatus = .idle
        detectedAt = Date()
        logger.info("Agent \(type.rawValue) set externally in session \(self.sessionID)")
    }

    // MARK: - Output Analysis

    /// Analyze a batch of terminal output to update agent status.
    /// Evaluates the status rule table top-to-bottom; first match wins.
    func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return .idle }

        let sample = String(text.suffix(AppConfig.Agent.outputAnalysisSuffixLength))

        if let matched = evaluateRules(sample) {
            currentStatus = matched
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
            tokenCount: tokenCount,
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
        StatusRule(.waitingInput, .contains("permission"), label: "permission-prompt"),

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
        StatusRule(.thinking, .contains("\u{2026}"), label: "ellipsis"),
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

// MARK: - Status Rule

/// A single, independently testable detection rule.
/// Each rule maps a text pattern to an `AgentStatus`.
struct StatusRule: Sendable {
    let status: AgentStatus
    let pattern: Pattern
    /// Human-readable label for debugging and test identification.
    let label: String

    init(_ status: AgentStatus, _ pattern: Pattern, label: String) {
        self.status = status
        self.pattern = pattern
        self.label = label
    }

    /// Returns true if the text matches this rule's pattern.
    func matches(_ text: String) -> Bool {
        pattern.evaluate(text)
    }

    /// Pattern types for flexible matching.
    enum Pattern: Sendable {
        case contains(String)
        case containsCaseInsensitive(String)
        case suffix(String)

        func evaluate(_ text: String) -> Bool {
            switch self {
            case let .contains(needle):
                text.contains(needle)
            case let .containsCaseInsensitive(needle):
                text.localizedCaseInsensitiveContains(needle)
            case let .suffix(needle):
                text.hasSuffix(needle)
            }
        }
    }
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Precompiled regex patterns for parsing token stats from agent output.
/// Hard-coded patterns are guaranteed well-formed; a compilation failure here would
/// indicate a system-level issue (e.g. ICU library missing). Falls back to a match-nothing
/// regex so the app degrades gracefully instead of crashing in production.
private enum TokenStatRegex {
    static let cost = compile("Total cost:\\s*\\$([\\d.]+)")
    static let input = compile("Input:\\s*([\\d,.]+)k?")
    static let output = compile("Output:\\s*([\\d,.]+)k?")
    static let cache = compile("Cache read:\\s*([\\d,.]+)k?")
    /// Matches "Writing to <path>" lines emitted by Claude Code and similar agents.
    static let writingTo = compile("Writing to ([^\\n\\r]+)")

    private static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        } catch {
            // Hard-coded patterns should never fail. Log at fault level but don't crash.
            assertionFailure("Failed to compile static regex '\(pattern)': \(error)")
            logger.fault("Failed to compile static regex '\(pattern)': \(error)")
            return NSRegularExpression()
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
    /// Last file path detected from "Writing to <path>" output; cleared on non-toolRunning transitions.
    private var activeFilePath: String?

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
    /// Rule table evaluated top-to-bottom (first match wins); cooldown and state-transition constraints suppress noise.
    @discardableResult
    func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return .idle }

        let sample = String(text.suffix(AppConfig.Agent.outputAnalysisSuffixLength))
        let lowercasedSample = sample.lowercased()

        guard let matched = evaluateRules(sample, lowercased: lowercasedSample),
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
        // Extract active file path when a tool-write is in progress; clear it otherwise.
        // Guard with a cheap contains() before running the regex to avoid unnecessary
        // regex execution when toolRunning was triggered by a different rule (e.g. "Running:").
        if matched == .toolRunning && sample.contains("Writing to") {
            activeFilePath = extractActiveFilePath(from: sample) ?? activeFilePath
        } else if matched == .idle || matched == .completed || matched == .error {
            activeFilePath = nil
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
            estimatedCostUSD: parsedCost,
            activeFilePath: activeFilePath,
            startedAt: detectedAt ?? Date()
        )
    }

    // MARK: - Active File Path Extraction

    /// Extracts a file path from "Writing to <path>" agent output, if present.
    private func extractActiveFilePath(from text: String) -> String? {
        let pattern = TokenStatRegex.writingTo
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange]).trimmingCharacters(in: .whitespaces)
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
        activeFilePath = nil
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
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        let captured = text[captureRange].replacingOccurrences(of: ",", with: "")
        guard let value = Double(captured) else { return nil }
        if let fullRange = Range(match.range, in: text),
           text[fullRange].lowercased().hasSuffix("k") {
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

    /// Pre-computed rule subsets per state — only rules leading to a valid transition are kept.
    private static let reachableRules: [AgentStatus: [StatusRule]] = validTransitions.reduce(into: [:]) { map, entry in
        map[entry.key] = statusRules.filter { entry.value.contains($0.status) }
    }

    /// Evaluates only the rules reachable from `currentStatus`, using a pre-lowercased sample.
    private func evaluateRules(_ text: String, lowercased lowercasedText: String) -> AgentStatus? {
        let rules = Self.reachableRules[currentStatus] ?? Self.statusRules
        for rule in rules where rule.matchesFast(text, lowercased: lowercasedText) {
            return rule.status
        }
        return nil
    }
}

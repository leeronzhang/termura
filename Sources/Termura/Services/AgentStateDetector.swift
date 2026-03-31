import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Precompiled regex patterns for token stats parsing.
/// Hard-coded patterns should never fail; falls back to a match-nothing regex so the
/// app degrades gracefully instead of crashing in production.
private enum TokenStatRegex {
    // Claude Code / OpenCode completion summary format:
    // "Total cost: $0.25 \n Input: 45.2k \n Output: 5.8k \n Cache read: 163.2k"
    static let cost = compile("Total cost:\\s*\\$([\\d.]+)")
    static let input = compile("Input:\\s*([\\d,.]+)k?")
    static let output = compile("Output:\\s*([\\d,.]+)k?")
    static let cache = compile("Cache read:\\s*([\\d,.]+)k?")

    // Aider completion summary format:
    // "Tokens: 8,423 sent, 432 received. Cost: $0.013 message, $0.237 session."
    // k-suffix is INSIDE the capture group (e.g. "8.4k sent"), handled by extractTokenCount.
    static let aiderSent = compile("([\\d,.]+k?)\\s+sent")
    static let aiderReceived = compile("([\\d,.]+k?)\\s+received")
    /// Matches the session-total cost in Aider's "Cost: $0.013 message, $0.237 session."
    static let aiderSessionCost = compile("\\$([\\d.]+)\\s+session")

    /// Matches "Writing to <path>" lines emitted by Claude Code and similar agents.
    static let writingTo = compile("Writing to ([^\\n\\r]+)")
    /// Matches "\u{23FA} Task: <description>" — Claude Code explicit task header lines.
    static let taskColon = compile("\u{23FA}\\s+Task:\\s+(.+?)\\s*$", options: [.caseInsensitive, .anchorsMatchLines])
    /// Matches "Working on: <description>" — generic agent status lines.
    static let workingOn = compile("Working on:\\s+(.+?)\\s*$", options: [.caseInsensitive, .anchorsMatchLines])
    /// Matches "\u{25CF} <description>" at start of a line — Claude Code tool-use preamble.
    /// Length-bounded (5-80 chars) to avoid matching long output blocks.
    static let bulletTask = compile("^\u{25CF}\\s+([^\n]{5,80})$", options: [.anchorsMatchLines])

    private static func compile(_ pattern: String, options: NSRegularExpression.Options = .caseInsensitive) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            // Hard-coded patterns should never fail — crash in debug, log+fallback in release.
            assertionFailure("Failed to compile static regex '\(pattern)': \(error)")
            logger.error("Failed to compile static regex '\(pattern)': \(error)")
            return NSRegularExpression()
        }
    }
}

/// Detects AI agent type and operational status from PTY output.
/// Uses startup command matching and ongoing output pattern analysis.
actor AgentStateDetector {
    private var detectedType: AgentType?
    var currentStatus: AgentStatus = .idle
    private var detectedAt: Date?
    private var lastStatusChange: Date?
    private var parsedCost: Double = 0
    private let sessionID: SessionID
    private let clock: any AppClock
    /// Last file path detected from "Writing to <path>" output; cleared on non-toolRunning transitions.
    private var activeFilePath: String?
    /// Brief description of what the agent is currently doing; populated from output patterns.
    private var currentTask: String?

    /// Valid state transitions — prevents impossible jumps between non-adjacent states.
    static let validTransitions: [AgentStatus: Set<AgentStatus>] = [
        .idle: [.thinking, .toolRunning, .waitingInput, .error],
        .thinking: [.toolRunning, .waitingInput, .completed, .error, .idle],
        .toolRunning: [.thinking, .waitingInput, .completed, .error, .idle],
        .waitingInput: [.thinking, .toolRunning, .idle, .error],
        .completed: [.idle, .thinking, .toolRunning],
        .error: [.idle, .thinking, .toolRunning, .waitingInput]
    ]

    init(sessionID: SessionID, clock: any AppClock = LiveClock()) {
        self.sessionID = sessionID
        self.clock = clock
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
                detectedAt = clock.now()
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
        detectedAt = clock.now()
        parsedCost = 0
        logger.info("Agent \(type.rawValue) set externally in session \(sid)")
    }

    // MARK: - Output Analysis

    /// Analyze a batch of terminal output; returns current status after processing.
    @discardableResult func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return currentStatus }
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        // Keep as Substring — avoids a String copy when text exceeds the analysis window.
        // Materialized to String only on the rare transition path where regex calls need it.
        let sample: Substring = text.count > maxLen ? text.suffix(maxLen) : text[text.startIndex...]
        // lowercased() allocates a new String; skip it entirely in states whose reachable
        // rule set contains no .containsCaseInsensitive rules (e.g. .completed, .error).
        let lowercasedSample: String = Self.statesNeedingLowercased.contains(currentStatus)
            ? sample.lowercased()
            : ""

        // Extract task description on every output batch in active states — not just on
        // transitions. Claude Code stays in toolRunning across many tool invocations without
        // a state change, so tying extraction to transitions means currentTask gets stuck.
        // extractCurrentTask has its own fast-path literal guard (O(1) when no anchor keyword).
        let sampleString = String(sample)
        if currentStatus == .toolRunning || currentStatus == .thinking {
            if let task = extractCurrentTask(from: sampleString) {
                currentTask = task
            }
        }

        guard let matched = evaluateRules(sample, lowercased: lowercasedSample),
              matched != currentStatus else { return currentStatus }

        // Enforce valid state transitions.
        guard Self.validTransitions[currentStatus]?.contains(matched) ?? false else { return currentStatus }

        // Enforce cooldown between transitions to avoid flip-flopping on noisy output.
        let now = clock.now()
        if let last = lastStatusChange,
           now.timeIntervalSince(last) < AppConfig.Agent.statusChangeCooldown { return currentStatus }

        currentStatus = matched
        lastStatusChange = now
        // Extract active file path when a tool-write is in progress; clear it otherwise.
        // Guard with a cheap contains() before running the regex to avoid unnecessary
        // regex execution when toolRunning was triggered by a different rule (e.g. "Running:").
        if matched == .toolRunning && sample.contains("Writing to") {
            activeFilePath = extractActiveFilePath(from: sampleString) ?? activeFilePath
        } else if matched == .idle || matched == .completed || matched == .error {
            activeFilePath = nil
        }
        // Clear task on terminal states; active-state extraction handled above.
        if matched == .idle || matched == .completed {
            currentTask = nil
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
            currentTask: currentTask,
            tokenCount: tokenCount,
            estimatedCostUSD: parsedCost,
            activeFilePath: activeFilePath,
            startedAt: detectedAt ?? clock.now()
        )
    }

    // MARK: - Task and File Path Extraction

    /// Extracts the current task description from agent output, if present.
    /// Fast-path: skips all regex if no anchor keyword is found.
    private func extractCurrentTask(from text: String) -> String? {
        guard text.contains("Task:") || text.contains("Working on:") || text.contains("\u{25CF}") else {
            return nil
        }
        let patterns: [NSRegularExpression] = [
            TokenStatRegex.taskColon,
            TokenStatRegex.workingOn,
            TokenStatRegex.bulletTask
        ]
        let range = NSRange(text.startIndex..., in: text)
        for pattern in patterns {
            guard let match = pattern.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else { continue }
            let captured = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !captured.isEmpty { return captured }
        }
        return nil
    }

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
    /// Dispatches to agent-specific parsers based on the detected agent type.
    func parseTokenStats(_ text: String) -> ParsedTokenStats? {
        switch detectedType {
        case .aider:
            return parseAiderStats(text)
        default:
            // Claude Code, OpenCode, and unrecognised agents all use the same summary format.
            return parseClaudeFormatStats(text)
        }
    }

    /// Claude Code / OpenCode completion summary:
    /// "Total cost: $0.25 | Input: 45.2k | Output: 5.8k | Cache read: 163.2k"
    private func parseClaudeFormatStats(_ text: String) -> ParsedTokenStats? {
        guard text.localizedCaseInsensitiveContains("Total cost:")
            || text.localizedCaseInsensitiveContains("Cache read:") else {
            return nil
        }
        var stats = ParsedTokenStats()
        var found = false
        if let cost = Self.extractDouble(from: text, pattern: Self.costPattern) {
            stats.totalCost = cost; found = true
        }
        if let input = Self.extractTokenCount(from: text, pattern: Self.inputPattern) {
            stats.inputTokens = input; found = true
        }
        if let output = Self.extractTokenCount(from: text, pattern: Self.outputPattern) {
            stats.outputTokens = output; found = true
        }
        if let cached = Self.extractTokenCount(from: text, pattern: Self.cachePattern) {
            stats.cachedTokens = cached; found = true
        }
        return found ? stats : nil
    }

    /// Aider completion summary:
    /// "Tokens: 8,423 sent, 432 received. Cost: $0.013 message, $0.237 session."
    private func parseAiderStats(_ text: String) -> ParsedTokenStats? {
        // Fast-path: Aider always prints "sent," on its summary line.
        guard text.contains("sent,") else { return nil }
        var stats = ParsedTokenStats()
        var found = false
        if let sent = Self.extractTokenCount(from: text, pattern: Self.aiderSentPattern) {
            stats.inputTokens = sent; found = true
        }
        if let received = Self.extractTokenCount(from: text, pattern: Self.aiderReceivedPattern) {
            stats.outputTokens = received; found = true
        }
        // "session" cost is the running total; "message" cost is per-turn only.
        if let cost = Self.extractDouble(from: text, pattern: Self.aiderSessionCostPattern) {
            stats.totalCost = cost; found = true
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
        currentTask = nil
    }

    // MARK: - Token Stat Patterns

    // Claude Code / OpenCode patterns
    private nonisolated static let costPattern = TokenStatRegex.cost
    private nonisolated static let inputPattern = TokenStatRegex.input
    private nonisolated static let outputPattern = TokenStatRegex.output
    private nonisolated static let cachePattern = TokenStatRegex.cache
    // Aider patterns
    private nonisolated static let aiderSentPattern = TokenStatRegex.aiderSent
    private nonisolated static let aiderReceivedPattern = TokenStatRegex.aiderReceived
    private nonisolated static let aiderSessionCostPattern = TokenStatRegex.aiderSessionCost

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
        let raw = String(text[captureRange])
        // k-suffix inside capture group (Aider: "8.4k sent" → capture "8.4k")
        if raw.lowercased().hasSuffix("k") {
            let digits = String(raw.dropLast()).replacingOccurrences(of: ",", with: "")
            guard let value = Double(digits) else { return nil }
            return Int(value * 1000)
        }
        let digits = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else { return nil }
        // k-suffix outside capture group (Claude Code: "Input: 45.2k" → capture "45.2", full match ends with "k")
        if let fullRange = Range(match.range, in: text),
           text[fullRange].lowercased().hasSuffix("k") {
            return Int(value * 1000)
        }
        return Int(value)
    }

}

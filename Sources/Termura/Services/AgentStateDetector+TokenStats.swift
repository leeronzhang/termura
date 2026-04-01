import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Precompiled regex patterns for token stats parsing.
/// Hard-coded patterns should never fail; falls back to a match-nothing regex so the
/// app degrades gracefully instead of crashing in production.
enum TokenStatRegex {
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

// MARK: - Task and File Path Extraction

extension AgentStateDetector {
    /// Extracts the current task description from agent output, if present.
    /// Fast-path: skips all regex if no anchor keyword is found.
    nonisolated func extractCurrentTask(from text: String) -> String? {
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
    nonisolated func extractActiveFilePath(from text: String) -> String? {
        let pattern = TokenStatRegex.writingTo
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Token Stats Parsing

extension AgentStateDetector {
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
        // k-suffix inside capture group (Aider: "8.4k sent" -> capture "8.4k")
        if raw.lowercased().hasSuffix("k") {
            let digits = String(raw.dropLast()).replacingOccurrences(of: ",", with: "")
            guard let value = Double(digits) else { return nil }
            return Int(value * 1000)
        }
        let digits = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else { return nil }
        // k-suffix outside capture group (Claude Code: "Input: 45.2k" -> capture "45.2", full match ends with "k")
        if let fullRange = Range(match.range, in: text),
           text[fullRange].lowercased().hasSuffix("k") {
            return Int(value * 1000)
        }
        return Int(value)
    }
}

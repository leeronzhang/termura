import Foundation

extension AgentStateDetector {
    /// Claude Code / OpenCode completion summary:
    /// "Total cost: $0.25 | Input: 45.2k | Output: 5.8k | Cache read: 163.2k"
    func parseClaudeFormatStats(_ text: String) -> ParsedTokenStats? {
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
    func parseAiderStats(_ text: String) -> ParsedTokenStats? {
        guard text.contains("sent,") else { return nil }
        var stats = ParsedTokenStats()
        var found = false
        if let sent = Self.extractTokenCount(from: text, pattern: Self.aiderSentPattern) {
            stats.inputTokens = sent; found = true
        }
        if let received = Self.extractTokenCount(from: text, pattern: Self.aiderReceivedPattern) {
            stats.outputTokens = received; found = true
        }
        if let cost = Self.extractDouble(from: text, pattern: Self.aiderSessionCostPattern) {
            stats.totalCost = cost; found = true
        }
        return found ? stats : nil
    }

    /// Codex CLI completion summary:
    /// "tokens: 5234 input + 678 output"  or  "tokens: 5.2k input, 678 output"
    /// "cost: $0.05"
    func parseCodexStats(_ text: String) -> ParsedTokenStats? {
        guard text.contains("input") && text.contains("output") else { return nil }
        var stats = ParsedTokenStats()
        var found = false
        if let input = Self.extractTokenCount(from: text, pattern: Self.codexInputPattern) {
            stats.inputTokens = input; found = true
        }
        if let output = Self.extractTokenCount(from: text, pattern: Self.codexOutputPattern) {
            stats.outputTokens = output; found = true
        }
        if let cost = Self.extractDouble(from: text, pattern: Self.codexCostPattern) {
            stats.totalCost = cost; found = true
        }
        return found ? stats : nil
    }

    /// Gemini CLI completion summary:
    /// "Token count: 1234 / 1048576"  or  "input_tokens: 1234  output_tokens: 567"
    func parseGeminiStats(_ text: String) -> ParsedTokenStats? {
        guard text.localizedCaseInsensitiveContains("token") else { return nil }
        var stats = ParsedTokenStats()
        var found = false
        if let input = Self.extractTokenCount(from: text, pattern: Self.geminiInputPattern) {
            stats.inputTokens = input; found = true
        }
        if let output = Self.extractTokenCount(from: text, pattern: Self.geminiOutputPattern) {
            stats.outputTokens = output; found = true
        }
        if !found, let total = Self.extractTokenCount(from: text, pattern: Self.geminiTokenCountPattern) {
            stats.inputTokens = total; found = true
        }
        return found ? stats : nil
    }

    // MARK: - Token Stat Patterns

    // Claude Code / OpenCode patterns
    nonisolated static let costPattern = TokenStatRegex.cost
    nonisolated static let inputPattern = TokenStatRegex.input
    nonisolated static let outputPattern = TokenStatRegex.output
    nonisolated static let cachePattern = TokenStatRegex.cache
    // Aider patterns
    nonisolated static let aiderSentPattern = TokenStatRegex.aiderSent
    nonisolated static let aiderReceivedPattern = TokenStatRegex.aiderReceived
    nonisolated static let aiderSessionCostPattern = TokenStatRegex.aiderSessionCost
    // Codex patterns
    nonisolated static let codexInputPattern = TokenStatRegex.codexInput
    nonisolated static let codexOutputPattern = TokenStatRegex.codexOutput
    nonisolated static let codexCostPattern = TokenStatRegex.codexCost
    // Gemini patterns
    nonisolated static let geminiTokenCountPattern = TokenStatRegex.geminiTokenCount
    nonisolated static let geminiInputPattern = TokenStatRegex.geminiInputTokens
    nonisolated static let geminiOutputPattern = TokenStatRegex.geminiOutputTokens

    static func extractDouble(
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

    static func extractTokenCount(
        from text: String,
        pattern: NSRegularExpression
    ) -> Int? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pattern.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        let raw = String(text[captureRange])
        if raw.lowercased().hasSuffix("k") {
            let digits = String(raw.dropLast()).replacingOccurrences(of: ",", with: "")
            guard let value = Double(digits) else { return nil }
            return Int(value * 1000)
        }
        let digits = raw.replacingOccurrences(of: ",", with: "")
        guard let value = Double(digits) else { return nil }
        if let fullRange = Range(match.range, in: text),
           text[fullRange].lowercased().hasSuffix("k") {
            return Int(value * 1000)
        }
        return Int(value)
    }
}

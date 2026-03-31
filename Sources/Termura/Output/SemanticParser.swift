import Foundation

/// Stateless parser that classifies raw PTY output into semantic content types.
/// Used by `ChunkDetector` to populate dual-track `OutputChunk` fields.
enum SemanticParser {
    /// Analyze output text and return its semantic classification + optional metadata.
    static func classify(_ text: String, command: String = "") -> Classification {
        if isDiff(text) {
            return Classification(type: .diff, language: nil, filePath: extractDiffPath(text))
        }
        if isError(text) {
            return Classification(type: .error, language: nil, filePath: nil)
        }
        if let language = detectCodeBlock(text) {
            return Classification(type: .code, language: language, filePath: nil)
        }
        if isToolCall(text) {
            return Classification(type: .toolCall, language: nil, filePath: nil)
        }
        return Classification(type: .commandOutput, language: nil, filePath: nil)
    }

    /// Lines-based overload — avoids materializing a joined prefix String.
    /// Called by `FallbackChunkDetector` and `ChunkDetector` which already hold `[String]`.
    static func classify(_ lines: [String], command: String = "") -> Classification {
        if isDiff(lines: lines) {
            return Classification(type: .diff, language: nil, filePath: extractDiffPath(lines: lines))
        }
        if isError(lines: lines) {
            return Classification(type: .error, language: nil, filePath: nil)
        }
        if let language = detectCodeBlock(lines: lines) {
            return Classification(type: .code, language: language, filePath: nil)
        }
        if isToolCall(lines: lines) {
            return Classification(type: .toolCall, language: nil, filePath: nil)
        }
        return Classification(type: .commandOutput, language: nil, filePath: nil)
    }

    /// Build a `UIContentBlock` from classification + raw lines.
    static func buildUIContent(
        from classification: Classification,
        displayLines: [String],
        exitCode: Int?
    ) -> UIContentBlock {
        UIContentBlock(
            type: classification.type,
            language: classification.language,
            filePath: classification.filePath,
            exitCode: exitCode,
            displayLines: displayLines
        )
    }

    // MARK: - Classification Result

    struct Classification: Sendable {
        let type: OutputContentType
        let language: String?
        let filePath: String?
    }

    // MARK: - Detection Heuristics (declarative pattern tables)

    /// Diff detection patterns — both conditions must match within the prefix.
    private static let diffPatterns: [[String]] = [
        ["--- a/", "+++ b/"],
        ["diff --git"]
    ]

    private static func isDiff(_ text: String) -> Bool {
        // Substring.contains(String) compiles via StringProtocol — no String copy needed.
        let sample = text.prefix(AppConfig.Output.diffDetectionPrefixLength)
        return diffPatterns.contains { group in
            group.allSatisfy { sample.contains($0) }
        }
    }

    private static func extractDiffPath(_ text: String) -> String? {
        // split returns zero-copy Substrings; no String allocated until a match is found.
        for line in text.split(separator: "\n", omittingEmptySubsequences: false)
            where line.hasPrefix("+++ b/") {
            return String(line.dropFirst(6))
        }
        return nil
    }

    /// Error indicator patterns (case-insensitive).
    static let errorIndicators: [String] = [
        "error:", "error[", "fatal:", "panic:",
        "traceback (most recent", "exception:",
        "failed:", "segmentation fault"
    ]

    private static func isError(_ text: String) -> Bool {
        // prefix() returns a Substring (zero-copy view); lowercased() on Substring
        // produces the final String in one step — saves the intermediate String allocation
        // compared to String(text.prefix(...)).lowercased().
        let lowered = text.prefix(AppConfig.Output.errorDetectionPrefixLength).lowercased()
        // Fast-path: errorIndicators are all specialised forms of these 7 root words.
        // Checking literal anchors first avoids the contains-in-contains scan on the
        // vast majority of clean command output (CLAUDE.md §3.7).
        guard lowered.contains("error")
            || lowered.contains("fatal")
            || lowered.contains("panic")
            || lowered.contains("traceback")
            || lowered.contains("exception")
            || lowered.contains("failed")
            || lowered.contains("segmentation") else {
            return false
        }
        return errorIndicators.contains { lowered.contains($0) }
    }

    private static func detectCodeBlock(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }
        let firstLine = trimmed.prefix(while: { $0 != "\n" })
        let lang = firstLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? "text" : lang
    }

    /// Tool-call indicator patterns (excludes rare-scalar entries; see `isToolCall`).
    static let toolCallIndicators: [String] = [
        "Tool:", "tool_use"
    ]

    private static func isToolCall(_ text: String) -> Bool {
        // prefix() returns a zero-copy Substring; both unicodeScalars and contains() are
        // available on Substring via StringProtocol — no String materialization needed.
        let sample = text.prefix(AppConfig.Output.toolCallDetectionPrefixLength)
        // Check the rare record-indicator scalar (\u{23FA}) via a scalar walk rather
        // than a standalone String.contains(), consistent with AgentStateDetector's
        // agentRareScalars gate. The two common-string indicators follow only if needed.
        if sample.unicodeScalars.contains("\u{23FA}") { return true }
        return toolCallIndicators.contains { sample.contains($0) }
    }

    // MARK: - Lines-based helpers (no String materialization)

    private static func isDiff(lines: [String]) -> Bool {
        let limit = AppConfig.Output.diffDetectionPrefixLength
        var consumed = 0
        var hasMinusMinus = false
        var hasPlusPlus = false
        for line in lines {
            if line.contains("diff --git") { return true }
            if line.contains("--- a/") { hasMinusMinus = true }
            if line.contains("+++ b/") { hasPlusPlus = true }
            if hasMinusMinus && hasPlusPlus { return true }
            consumed += line.count + 1
            if consumed >= limit { break }
        }
        return false
    }

    private static func extractDiffPath(lines: [String]) -> String? {
        for line in lines where line.hasPrefix("+++ b/") {
            return String(line.dropFirst(6))
        }
        return nil
    }

    private static func isError(lines: [String]) -> Bool {
        let limit = AppConfig.Output.errorDetectionPrefixLength
        var consumed = 0
        for line in lines {
            let lowered = line.lowercased()
            // Fast-path: skip lines that cannot possibly match any errorIndicator (CLAUDE.md §3.7).
            guard lowered.contains("error")
                || lowered.contains("fatal")
                || lowered.contains("panic")
                || lowered.contains("traceback")
                || lowered.contains("exception")
                || lowered.contains("failed")
                || lowered.contains("segmentation") else {
                consumed += line.count + 1
                if consumed >= limit { break }
                continue
            }
            if errorIndicators.contains(where: { lowered.contains($0) }) { return true }
            consumed += line.count + 1
            if consumed >= limit { break }
        }
        return false
    }

    private static func detectCodeBlock(lines: [String]) -> String? {
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard trimmed.hasPrefix("```") else { return nil }
            let firstLine = trimmed.prefix(while: { $0 != "\n" })
            let lang = firstLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
            return lang.isEmpty ? "text" : lang
        }
        return nil
    }

    private static func isToolCall(lines: [String]) -> Bool {
        let limit = AppConfig.Output.toolCallDetectionPrefixLength
        var consumed = 0
        for line in lines {
            if line.unicodeScalars.contains("\u{23FA}") { return true }
            if toolCallIndicators.contains(where: { line.contains($0) }) { return true }
            consumed += line.count + 1
            if consumed >= limit { break }
        }
        return false
    }
}

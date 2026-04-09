import Foundation

extension SemanticParser {
    /// Lines-based overload — avoids materializing a joined prefix String.
    /// Called by `FallbackChunkDetector` and `ChunkDetector` which already hold `[String]`.
    static func classify(_ lines: [String], command: String = "") -> Classification {
        if isDiff(lines: lines) {
            return Classification(type: .diff, language: nil, filePath: extractDiffPath(lines: lines))
        }
        if isError(lines: lines) {
            return Classification(type: .error, language: nil, filePath: nil)
        }
        if isMarkdown(lines: lines) {
            return Classification(type: .markdown, language: nil, filePath: nil)
        }
        if let language = detectCodeBlock(lines: lines) {
            return Classification(type: .code, language: language, filePath: nil)
        }
        if isToolCall(lines: lines) {
            return Classification(type: .toolCall, language: nil, filePath: nil)
        }
        return Classification(type: .commandOutput, language: nil, filePath: nil)
    }

    static func isMarkdown(lines: [String]) -> Bool {
        var signals = 0
        var hasHeading = false
        var hasList = false
        var hasCodeFence = false
        var hasBlockquote = false
        for line in lines {
            let trimmed = line.drop(while: { $0 == " " })
            if !hasHeading && trimmed.hasPrefix("#") && trimmed.dropFirst().first == " " {
                hasHeading = true
                signals += 1
            }
            if !hasList && (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")) {
                hasList = true
                signals += 1
            }
            if !hasCodeFence && trimmed.hasPrefix("```") {
                hasCodeFence = true
                signals += 1
            }
            if !hasBlockquote && trimmed.hasPrefix("> ") {
                hasBlockquote = true
                signals += 1
            }
            if signals >= markdownSignalThreshold { return true }
        }
        return false
    }

    static func isDiff(lines: [String]) -> Bool {
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

    static func extractDiffPath(lines: [String]) -> String? {
        for line in lines where line.hasPrefix("+++ b/") {
            return String(line.dropFirst(6))
        }
        return nil
    }

    static func isError(lines: [String]) -> Bool {
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

    static func detectCodeBlock(lines: [String]) -> String? {
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

    static func isToolCall(lines: [String]) -> Bool {
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

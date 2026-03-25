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

    // MARK: - Detection Heuristics

    private static func isDiff(_ text: String) -> Bool {
        let lines = text.prefix(AppConfig.Output.diffDetectionPrefixLength)
        return lines.contains("--- a/") && lines.contains("+++ b/")
            || lines.contains("diff --git")
    }

    private static func extractDiffPath(_ text: String) -> String? {
        for line in text.components(separatedBy: "\n") where line.hasPrefix("+++ b/") {
            return String(line.dropFirst(6))
        }
        return nil
    }

    private static func isError(_ text: String) -> Bool {
        let lowered = text.lowercased().prefix(AppConfig.Output.errorDetectionPrefixLength)
        let errorIndicators = [
            "error:", "error[", "fatal:", "panic:",
            "traceback (most recent", "exception:",
            "failed:", "segmentation fault"
        ]
        return errorIndicators.contains { lowered.contains($0) }
    }

    private static func detectCodeBlock(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return nil }
        let firstLine = trimmed.prefix(while: { $0 != "\n" })
        let lang = firstLine.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return lang.isEmpty ? "text" : lang
    }

    private static func isToolCall(_ text: String) -> Bool {
        let prefix = text.prefix(AppConfig.Output.toolCallDetectionPrefixLength)
        return prefix.contains("\u{23FA}") || prefix.contains("Tool:") || prefix.contains("tool_use")
    }
}

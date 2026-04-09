import Foundation

extension SessionHandoffService {
    /// Keywords used to identify error lines when summarising output chunks.
    /// Checked case-insensitively against lowercased line content.
    static let errorLineKeywords: [String] = [
        "error", "fatal", "traceback", "panic", "failed"
    ]

    // MARK: - Extraction Heuristics

    func extractDecisions(from chunks: [OutputChunk]) -> [DecisionEntry] {
        let decisionKeywords = [
            "chose", "decided", "because", "instead of",
            "switched to", "going with", "picked", "selected"
        ]
        var entries: [DecisionEntry] = []

        for chunk in chunks {
            for line in chunk.outputLines {
                let lower = line.lowercased()
                let matches = decisionKeywords.contains { lower.contains($0) }
                if matches {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty,
                          trimmed.count > AppConfig.SessionHandoff.minDecisionLineLength else { continue }
                    let entry = DecisionEntry(
                        timestamp: chunk.startedAt,
                        summary: String(trimmed.prefix(AppConfig.SessionHandoff.entryLineMaxLength))
                    )
                    entries.append(entry)
                }
            }
        }

        return Array(entries.prefix(AppConfig.SessionHandoff.maxHandoffDecisions))
    }

    func extractErrors(from chunks: [OutputChunk]) -> [String] {
        var errors: [String] = []

        for chunk in chunks where chunk.contentType == .error || (chunk.exitCode ?? 0) != 0 {
            for line in chunk.outputLines.prefix(AppConfig.SessionHandoff.maxErrorLinesPerChunk) {
                let lower = line.lowercased()
                let isError = Self.errorLineKeywords.contains(where: lower.contains)
                if isError {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    errors.append(String(trimmed.prefix(AppConfig.SessionHandoff.entryLineMaxLength)))
                }
            }
        }

        return Array(errors.prefix(AppConfig.SessionHandoff.maxHandoffErrors))
    }
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ExperienceCodifier")

/// Converts agent error context into a rule draft and appends it to a harness file.
/// The append is also recorded as a `HarnessEvent` in the session metadata layer.
actor ExperienceCodifier {
    private let harnessEventRepo: any HarnessEventRepositoryProtocol

    init(harnessEventRepo: any HarnessEventRepositoryProtocol) {
        self.harnessEventRepo = harnessEventRepo
    }

    /// Generate a rule draft from error context.
    func generateDraft(from chunk: OutputChunk) -> RuleDraft {
        let errorSummary = extractErrorSummary(chunk)
        let ruleText = """
        ## Avoid: \(errorSummary.title)

        When \(errorSummary.context), do not \(errorSummary.antiPattern).
        Instead, \(errorSummary.suggestion).

        <!-- Codified from session error on \(ISO8601DateFormatter().string(from: Date())) -->
        """
        return RuleDraft(
            errorChunkID: chunk.id,
            sessionID: chunk.sessionID,
            suggestedRule: ruleText,
            errorSummary: errorSummary
        )
    }

    /// Append a confirmed rule to a harness file and record the event.
    func appendRule(
        draft: RuleDraft,
        to filePath: String,
        sessionID: SessionID
    ) async throws {
        // Read current file
        let currentContent = try String(contentsOfFile: filePath, encoding: .utf8)

        // Backup before write
        let backupPath = filePath + ".backup"
        try currentContent.write(toFile: backupPath, atomically: true, encoding: .utf8)

        // Append the rule
        let newContent = currentContent + "\n\n" + draft.suggestedRule + "\n"
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Clean up backup
        do {
            try FileManager.default.removeItem(atPath: backupPath)
        } catch {
            // Non-critical: stale backup is harmless and will be overwritten on next rule append.
            logger.warning("Failed to remove backup rule file: \(error)")
        }

        // Record harness event
        let event = HarnessEvent(
            sessionID: sessionID,
            eventType: .ruleAppend,
            payload: "{\"file\":\"\(filePath)\",\"rule\":\"\(draft.errorSummary.title)\"}"
        )
        try await harnessEventRepo.save(event)

        logger.info("Appended rule to \(filePath): \(draft.errorSummary.title)")
    }

    // MARK: - Error Analysis

    private func extractErrorSummary(_ chunk: OutputChunk) -> ErrorSummary {
        let firstErrorLine = chunk.outputLines.first {
            $0.lowercased().contains("error") || $0.lowercased().contains("fatal")
        } ?? chunk.outputLines.first ?? "Unknown error"

        let title = String(firstErrorLine.prefix(80))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let context = chunk.commandText.isEmpty ? "running this operation" : "running `\(chunk.commandText)`"

        return ErrorSummary(
            title: title,
            context: context,
            antiPattern: "repeat this pattern without safeguards",
            suggestion: "add proper error handling or precondition checks"
        )
    }
}

// MARK: - Supporting Types

struct RuleDraft: Sendable {
    let errorChunkID: UUID
    let sessionID: SessionID
    let suggestedRule: String
    let errorSummary: ErrorSummary
}

struct ErrorSummary: Sendable {
    let title: String
    let context: String
    let antiPattern: String
    let suggestion: String
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ExperienceCodifier")

/// Converts agent error context into a rule draft and appends it to a harness file.
actor ExperienceCodifier {
    private let harnessEventRepo: any HarnessEventRepositoryProtocol
    private let clock: @Sendable () -> Date

    init(
        harnessEventRepo: any HarnessEventRepositoryProtocol,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.harnessEventRepo = harnessEventRepo
        self.clock = clock
    }

    func generateDraft(from chunk: OutputChunk) -> RuleDraft {
        let errorSummary = extractErrorSummary(chunk)
        let ruleText = """
        ## Avoid: \(errorSummary.title)

        When \(errorSummary.context), do not \(errorSummary.antiPattern).
        Instead, \(errorSummary.suggestion).

        <!-- Codified from session error on \(ISO8601DateFormatter().string(from: clock())) -->
        """
        return RuleDraft(
            errorChunkID: chunk.id,
            sessionID: chunk.sessionID,
            suggestedRule: ruleText,
            errorSummary: errorSummary
        )
    }

    func appendRule(draft: RuleDraft, to filePath: String, sessionID: SessionID) async throws {
        let currentContent = try String(contentsOfFile: filePath, encoding: .utf8)
        let backupPath = filePath + ".backup"
        try currentContent.write(toFile: backupPath, atomically: true, encoding: .utf8)
        let newContent = currentContent + "\n\n" + draft.suggestedRule + "\n"
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        defer {
            // Non-critical: backup cleanup on the rule-append happy path. The
            // file is a transient `.backup` next to a successfully rewritten
            // target; a stale backup is harmless and gets overwritten on the
            // next append. Don't promote the failure to a thrown error here —
            // it would shadow the actual happy-path result.
            do {
                try FileManager.default.removeItem(atPath: backupPath)
            } catch {
                logger.warning("backup cleanup failed at \(backupPath): \(error.localizedDescription)")
            }
        }
        let event = HarnessEvent(
            sessionID: sessionID,
            eventType: .ruleAppend,
            payload: "{\"file\":\"\(filePath)\",\"rule\":\"\(draft.errorSummary.title)\"}"
        )
        try await harnessEventRepo.save(event)
        logger.info("Appended rule to \(filePath): \(draft.errorSummary.title)")
    }

    private func extractErrorSummary(_ chunk: OutputChunk) -> ErrorSummary {
        let firstErrorLine = chunk.outputLines.first {
            $0.lowercased().contains("error") || $0.lowercased().contains("fatal")
        } ?? chunk.outputLines.first ?? "Unknown error"
        let title = String(firstErrorLine.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        let context = chunk.commandText.isEmpty ? "running this operation" : "running `\(chunk.commandText)`"
        return ErrorSummary(
            title: title,
            context: context,
            antiPattern: "repeat this pattern without safeguards",
            suggestion: "add proper error handling or precondition checks"
        )
    }
}

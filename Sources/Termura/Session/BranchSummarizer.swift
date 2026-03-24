import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "BranchSummarizer")

/// Generates a summary of a completed branch session.
/// Currently uses a heuristic extractor; can be extended to call local/remote LLM.
actor BranchSummarizer {
    /// Generate a summary from the session's output chunks.
    func summarize(chunks: [OutputChunk], branchType: BranchType) -> String {
        guard !chunks.isEmpty else { return "Empty branch session." }

        let commandCount = chunks.count
        let errorCount = chunks.count(where: { $0.exitCode != nil && $0.exitCode != 0 })
        let commands = chunks.compactMap { $0.commandText.isEmpty ? nil : $0.commandText }
        let topCommands = Array(commands.prefix(5))

        var summary = "[\(branchType.rawValue.capitalized)] "
        summary += "\(commandCount) command\(commandCount == 1 ? "" : "s")"

        if errorCount > 0 {
            summary += ", \(errorCount) error\(errorCount == 1 ? "" : "s")"
        }

        if !topCommands.isEmpty {
            let cmdList = topCommands.map { "`\($0)`" }.joined(separator: ", ")
            summary += ". Key commands: \(cmdList)"
        }

        // Extract any key findings from error chunks
        let errorLines = chunks
            .filter { $0.contentType == .error }
            .flatMap { $0.outputLines.prefix(3) }
            .prefix(5)

        if !errorLines.isEmpty {
            summary += ". Errors: " + errorLines.joined(separator: "; ")
        }

        return String(summary.prefix(AppConfig.SessionTree.summaryMaxLength))
    }

    /// Create a metadata message containing the branch summary.
    func createSummaryMessage(
        summary: String,
        branchSessionID: SessionID,
        parentSessionID: SessionID
    ) -> SessionMessage {
        SessionMessage(
            sessionID: parentSessionID,
            role: .system,
            contentType: .metadata,
            content: "[Branch \(branchSessionID) summary] \(summary)"
        )
    }
}

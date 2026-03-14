import Foundation

/// A structured, identifiable unit of terminal output corresponding to one command execution.
/// `outputLines` are ANSI-stripped for display/copy; `rawANSI` preserves escape sequences.
struct OutputChunk: Identifiable, Sendable {
    let id: UUID
    let sessionID: SessionID
    /// The command text that produced this output.
    let commandText: String
    /// ANSI-stripped output lines for display and clipboard.
    let outputLines: [String]
    /// Raw ANSI output preserving escape sequences.
    let rawANSI: String
    /// Shell exit code; nil if not reported.
    let exitCode: Int?
    let startedAt: Date
    let finishedAt: Date?
    /// Whether the chunk body is collapsed in the UI.
    var isCollapsed: Bool
    /// Heuristic: total chars / 4 ≈ tokens.
    var estimatedTokens: Int

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        commandText: String,
        outputLines: [String],
        rawANSI: String,
        exitCode: Int?,
        startedAt: Date,
        finishedAt: Date?,
        isCollapsed: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.commandText = commandText
        self.outputLines = outputLines
        self.rawANSI = rawANSI
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.isCollapsed = isCollapsed
        let charCount = outputLines.joined().count
        self.estimatedTokens = max(1, charCount / Int(AppConfig.AI.tokenEstimateDivisor))
    }
}

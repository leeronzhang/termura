import Foundation

/// A structured, identifiable unit of terminal output corresponding to one command execution.
///
/// Follows the LLM/UI side separation protocol:
/// - `modelContent`: raw text preserved for LLM context (if needed).
/// - `uiContent`: structured block consumed by the UI layer for card rendering.
/// - `outputLines` / `rawANSI`: legacy fields retained for backward compatibility.
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
    /// Semantic classification of this output block.
    let contentType: OutputContentType
    /// Raw text kept for model context — the LLM side of dual-track.
    let modelContent: String
    /// Structured data for UI rendering — the UI side of dual-track.
    let uiContent: UIContentBlock

    init(
        id: UUID = UUID(),
        sessionID: SessionID,
        commandText: String,
        outputLines: [String],
        rawANSI: String,
        exitCode: Int?,
        startedAt: Date,
        finishedAt: Date?,
        isCollapsed: Bool = false,
        contentType: OutputContentType = .commandOutput,
        uiContent: UIContentBlock? = nil
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
        estimatedTokens = max(1, charCount / Int(AppConfig.AI.tokenEstimateDivisor))
        self.contentType = contentType
        modelContent = rawANSI
        self.uiContent = uiContent ?? UIContentBlock(
            type: contentType,
            exitCode: exitCode,
            displayLines: outputLines
        )
    }
}

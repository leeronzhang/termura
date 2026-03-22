import Foundation

/// Structured UI-side representation of an output block.
/// The UI layer consumes this for rendering — no raw text parsing needed.
/// Paired with `modelContent` (raw text for LLM) in `OutputChunk`.
struct UIContentBlock: Sendable {
    /// Semantic type determining the rendering card style.
    let type: OutputContentType
    /// Programming language identifier (e.g. "swift", "python") — for code blocks.
    let language: String?
    /// Associated file path — for diff blocks or file-related output.
    let filePath: String?
    /// Shell exit code — for command output blocks.
    let exitCode: Int?
    /// Pre-processed display lines (ANSI-stripped, ready for rendering).
    let displayLines: [String]

    init(
        type: OutputContentType,
        language: String? = nil,
        filePath: String? = nil,
        exitCode: Int? = nil,
        displayLines: [String] = []
    ) {
        self.type = type
        self.language = language
        self.filePath = filePath
        self.exitCode = exitCode
        self.displayLines = displayLines
    }
}

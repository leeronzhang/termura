import Foundation

/// Classifies the semantic type of a terminal output block.
/// Used by the dual-track output protocol to determine rendering strategy.
enum OutputContentType: String, Sendable, Codable, CaseIterable {
    /// Source code block (with optional language tag).
    case code
    /// Unified diff output.
    case diff
    /// Error message or stack trace.
    case error
    /// Plain text / prose output.
    case text
    /// Agent tool call invocation or result.
    case toolCall
    /// Standard command output (ls, git status, etc.).
    case commandOutput
    /// Markdown-formatted content (headings, lists, fenced code blocks).
    case markdown
}

import Foundation

/// Shared FTS5 query escaping used by all repositories with full-text search.
enum FTS5 {
    /// Escapes user input for safe use in an FTS5 MATCH expression.
    ///
    /// Wraps the entire input in double quotes, making all FTS5 operators
    /// (`*`, `()`, `:`, `AND`/`OR`/`NOT`, `^`) literal. The only character
    /// requiring escape inside FTS5 double quotes is `"` itself (doubled to `""`).
    /// A trailing `*` enables prefix matching on the last token.
    static func escapeQuery(_ raw: String) -> String {
        let sanitized = raw
            .replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\"", with: "\"\"")
        guard !sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "\"\""
        }
        return "\"\(sanitized)\"*"
    }
}

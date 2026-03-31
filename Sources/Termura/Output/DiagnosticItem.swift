import Foundation

/// Severity level of a compiler or linter diagnostic.
enum DiagnosticSeverity: String, Sendable, CaseIterable {
    case error
    case warning
    case note
}

/// A single compiler or linter diagnostic extracted from terminal output.
struct DiagnosticItem: Identifiable, Sendable {
    let id: UUID
    /// File path, normalized relative to project root when the output contains an absolute path.
    let file: String
    let line: Int?
    let column: Int?
    let severity: DiagnosticSeverity
    let message: String
    /// Derived from the command that produced this diagnostic (e.g., "swift", "swiftlint", "tsc").
    let source: String
    let sessionID: SessionID
    let producedAt: Date
    /// Display name: last path component only (e.g., "ContentView.swift").
    /// Stored once at init — `file` is immutable so URL parsing is not repeated on each access.
    let fileName: String

    init(
        id: UUID,
        file: String,
        line: Int?,
        column: Int?,
        severity: DiagnosticSeverity,
        message: String,
        source: String,
        sessionID: SessionID,
        producedAt: Date
    ) {
        self.id = id
        self.file = file
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
        self.source = source
        self.sessionID = sessionID
        self.producedAt = producedAt
        self.fileName = URL(fileURLWithPath: file).lastPathComponent
    }

    /// One-line location string for display (e.g., "ContentView.swift:42").
    var locationLabel: String {
        guard let line else { return fileName }
        return "\(fileName):\(line)"
    }
}

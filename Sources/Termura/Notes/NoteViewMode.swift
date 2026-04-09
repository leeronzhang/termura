import Foundation

/// Display mode for an open note tab.
enum NoteViewMode: String, CaseIterable, Sendable {
    /// Source markdown editor (NSTextView with syntax highlighting).
    case edit
    /// Rendered markdown view (WKWebView).
    case reading
}

import SwiftUI

/// Describes a session's membership in a split tab pair.
struct SplitMembership: Hashable {
    let partnerSessionID: SessionID
    let partnerTitle: String
    /// Whether this split tab is the currently selected tab.
    let isActiveTab: Bool
    let paneSlot: PaneSlot
}

/// Identifies an open tab in the main content area.
/// Terminal tabs carry a SessionID; split tabs carry two session IDs.
enum ContentTab: Identifiable, Hashable, Codable {
    case terminal(sessionID: SessionID, title: String)
    case split(left: SessionID, right: SessionID, leftTitle: String, rightTitle: String)
    case note(noteID: NoteID, title: String)
    case noteSplit(left: NoteID, right: NoteID, leftTitle: String, rightTitle: String)
    case diff(path: String, isStaged: Bool, isUntracked: Bool)
    case file(path: String, name: String)
    case preview(path: String, name: String)

    var id: String {
        switch self {
        case let .terminal(sessionID, _): "terminal-\(sessionID)"
        case let .split(left, right, _, _): "split-\(left)-\(right)"
        case let .note(noteID, _): "note-\(noteID)"
        case let .noteSplit(left, right, _, _): "notesplit-\(left)-\(right)"
        case let .diff(path, isStaged, _): "diff-\(isStaged ? "staged" : "wt")-\(path)"
        case let .file(path, _): "file-\(path)"
        case let .preview(path, _): "preview-\(path)"
        }
    }

    var title: String {
        switch self {
        case let .terminal(_, title):
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terminal" : title
        case let .split(_, _, leftTitle, rightTitle):
            let left = leftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terminal" : leftTitle
            let right = rightTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Terminal" : rightTitle
            return "\(left) | \(right)"
        case let .note(_, title): return title.isEmpty ? "Untitled" : title
        case let .noteSplit(_, _, leftTitle, rightTitle):
            let left = leftTitle.isEmpty ? "Untitled" : leftTitle
            let right = rightTitle.isEmpty ? "Untitled" : rightTitle
            return "\(left) | \(right)"
        case let .diff(path, _, _): return URL(fileURLWithPath: path).lastPathComponent
        case let .file(_, name): return name
        case let .preview(_, name): return name
        }
    }

    var icon: String {
        switch self {
        case .terminal: "terminal"
        case .split: "rectangle.split.2x1"
        case .note: "doc.text"
        case .noteSplit: "rectangle.split.2x1"
        case .diff: "doc.text.magnifyingglass"
        case .file: "doc.text"
        case .preview: "eye"
        }
    }

    /// Filename to resolve via FileTypeIcon for asset-based icons.
    /// Returns nil for terminal/split tabs which use SF Symbols.
    var fileTypeIconName: String? {
        switch self {
        case .terminal, .split: nil
        case .note, .noteSplit: "readme.md"
        case let .diff(path, _, _): URL(fileURLWithPath: path).lastPathComponent
        case let .file(_, name): name
        case let .preview(_, name): name
        }
    }

    /// Whether the tab shows a close (xmark) button in the tab bar.
    /// Closing a terminal tab ends the session (PTY terminated, record preserved).
    /// Closing a split tab ends the focused pane session.
    var isClosable: Bool {
        switch self {
        case .terminal, .split: true
        case .note, .noteSplit, .diff, .file, .preview: true
        }
    }

    /// Whether this tab represents a single terminal session.
    var isTerminal: Bool {
        if case .terminal = self { return true }
        return false
    }

    /// Whether this tab is a split pair of two terminal sessions.
    var isSplit: Bool {
        if case .split = self { return true }
        return false
    }

    /// Whether this tab is a Markdown note editor (single or split).
    var isNote: Bool {
        switch self {
        case .note, .noteSplit: true
        default: false
        }
    }

    /// Whether this tab is a split pair of two note editors.
    var isNoteSplit: Bool {
        if case .noteSplit = self { return true }
        return false
    }

    /// Whether this tab is a project-level content tab (file, diff, or preview).
    var isProjectContent: Bool {
        switch self {
        case .file, .preview, .diff: true
        case .terminal, .split, .note, .noteSplit: false
        }
    }

    /// The session ID if this is a single terminal tab.
    var sessionID: SessionID? {
        if case let .terminal(sessionID, _) = self { return sessionID }
        return nil
    }

    /// The left and right session IDs if this is a split tab.
    var splitSessionIDs: (left: SessionID, right: SessionID)? {
        if case let .split(left, right, _, _) = self { return (left, right) }
        return nil
    }

    /// The left and right note IDs if this is a note split tab.
    var splitNoteIDs: (left: NoteID, right: NoteID)? {
        if case let .noteSplit(left, right, _, _) = self { return (left, right) }
        return nil
    }

    /// Whether either slot of this tab contains the given session.
    func containsSession(_ id: SessionID) -> Bool {
        switch self {
        case let .terminal(sid, _): sid == id
        case let .split(left, right, _, _): left == id || right == id
        case .note, .noteSplit, .diff, .file, .preview: false
        }
    }

    /// Whether either slot of this tab contains the given note.
    func containsNote(_ id: NoteID) -> Bool {
        switch self {
        case let .note(noteID, _): noteID == id
        case let .noteSplit(left, right, _, _): left == id || right == id
        default: false
        }
    }

    /// The file path if this is a file, preview, or diff tab.
    var filePath: String? {
        switch self {
        case let .file(path, _), let .preview(path, _), let .diff(path, _, _):
            path
        case .terminal, .split, .note, .noteSplit:
            nil
        }
    }
}

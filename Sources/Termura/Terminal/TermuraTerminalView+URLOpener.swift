import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalURLOpener")

// MARK: - URL opening (Cmd+click)

extension TermuraTerminalView {

    // MARK: Cell coordinate helpers

    /// Replicates SwiftTerm's internal `computeFontDimensions` formula
    /// (AppleTerminalView.swift line 162-186) so coordinate math is consistent
    /// with SwiftTerm's hit-testing without requiring access to the internal
    /// `cellDimension` property, which is not public outside the SwiftTerm module.
    func terminalCellSize() -> CGSize {
        let cellWidth = font.advancement(forGlyph: font.glyph(withName: "W")).width
        let cellHeight = ceil(font.ascender - font.descender + font.leading)
        return CGSize(width: max(1, cellWidth), height: max(1, cellHeight))
    }

    /// Converts a view-local NSPoint to a terminal (col, row) pair relative to the
    /// visible viewport. Row 0 is the topmost visible line. Returns nil when the
    /// point lies outside the cell grid.
    func visibleCell(at point: NSPoint) -> (col: Int, row: Int)? {
        let cell = terminalCellSize()
        let col = Int(point.x / cell.width)
        let row = Int((bounds.height - point.y) / cell.height)
        guard col >= 0, col < terminal.cols, row >= 0, row < terminal.rows else { return nil }
        return (col, row)
    }

    // MARK: URL extraction

    /// Returns the OSC 8 hyperlink URL for the cell at (col, row), or nil.
    /// SwiftTerm stores the payload as `"params;url"` (params may be empty).
    func osc8URL(col: Int, row: Int) -> URL? {
        guard let payload = terminal.getCharData(col: col, row: row)?.getPayload() as? String else {
            return nil
        }
        // Split on the first ";" only — the URL itself may legally contain semicolons.
        let parts = payload.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        return URL(string: String(parts[1]))
    }

    /// Cached NSDataDetector for link detection.
    /// NSDataDetector is expensive to create but thread-safe for `matches` calls.
    /// The static-let closure runs once for the class lifetime.
    static let linkDetector: NSDataDetector? = {
        do {
            return try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        } catch {
            logger.error("NSDataDetector init failed, plain-text URL detection disabled: \(error)")
            return nil
        }
    }()

    /// Reads the visible terminal line at `row`, then uses NSDataDetector to find
    /// any URL whose character range contains `col`. Returns the first match, or nil.
    /// Handles plain-text https:// and file:// links not encoded as OSC 8.
    func plainTextURL(col: Int, row: Int) -> URL? {
        var lineText = ""
        lineText.reserveCapacity(terminal.cols)
        for colIdx in 0..<terminal.cols {
            lineText.append(terminal.getCharacter(col: colIdx, row: row) ?? " ")
        }
        let range = NSRange(location: 0, length: (lineText as NSString).length)
        let matches = Self.linkDetector?.matches(in: lineText, range: range) ?? []
        for match in matches where match.range.location <= col
                && col < match.range.location + match.range.length {
            return match.url
        }
        return nil
    }

    // MARK: URL dispatch

    /// Opens `url` in the system default application:
    /// - `file://` paths are revealed in Finder via `activateFileViewerSelecting`.
    /// - All other schemes (http, https, …) open in the default browser.
    func openTerminalURL(_ url: URL) {
        if url.scheme == "file" {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

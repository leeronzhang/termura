import Foundation
import GhosttyKit

/// Read-only accessors over `GhosttyTerminalView.readVisibleText()` plus the
/// scrollback-navigation surface required by the `TerminalEngine` protocol.
/// Lives in its own file to keep the main `LibghosttyEngine` under the
/// file-length budget; behaviour is unchanged from the pre-W2 inline form.
extension LibghosttyEngine {
    func cursorLineContent() -> String? {
        let lines = ghosttyView.readVisibleText().split(separator: "\n", omittingEmptySubsequences: false)
        return lines.last { !$0.allSatisfy(\.isWhitespace) }.map(String.init)
    }

    func readVisibleScreen() -> TerminalScreenSnapshot? {
        guard let surface = ghosttyView.surface else { return nil }
        let size = ghostty_surface_size(surface)
        let lines = ghosttyView.readVisibleText()
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return TerminalScreenSnapshot(rows: Int(size.rows), cols: Int(size.columns), lines: lines)
    }

    func linesNearCursor(above count: Int) -> [String] {
        let all = ghosttyView.readVisibleText().split(separator: "\n", omittingEmptySubsequences: false)
        guard !all.isEmpty else { return [] }
        let start = max(0, all.count - count - 1)
        return all[start...].map(String.init)
    }

    func currentScrollLine() -> Int {
        // TODO: expose ghostty scroll position via C API
        0
    }

    func scrollToLine(_ line: Int) async {
        _ = line
        // TODO: expose ghostty scroll via C API
    }

    var supportsScrollbackNavigation: Bool { false }
}

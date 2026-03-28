import Foundation

extension TerminalViewModel {
    // MARK: - Agent detection from screen buffer

    /// Read lines near the cursor from the screen buffer and detect the agent from the
    /// typed command. Called on executionStarted (OSC 133;C) so any command entered
    /// directly in the terminal triggers detection immediately — not just Composer input.
    func detectAgentFromCurrentLine() {
        for line in engine.linesNearCursor(above: 5).reversed() {
            let cmd = shellCommandFrom(line)
            guard !cmd.isEmpty else { continue }
            detectAgentFromCommand(cmd)
            return
        }
    }

    /// Extract the command portion from a shell prompt line.
    /// Handles formats like "user@host ~/path $ cmd", "% cmd", "$ cmd".
    private func shellCommandFrom(_ line: String) -> String {
        let s = line.trimmingCharacters(in: .whitespaces)
        for delimiter in [" $ ", " % ", " > ", " # "] {
            if let range = s.range(of: delimiter, options: .backwards) {
                let cmd = String(s[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !cmd.isEmpty { return cmd }
            }
        }
        for prefix in ["$ ", "% ", "> ", "# "] where s.hasPrefix(prefix) {
            return String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }
}

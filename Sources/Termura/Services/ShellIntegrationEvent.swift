import Foundation

/// Events emitted when OSC 133 sequences are parsed from terminal output.
/// Each value maps to a specific shell integration marker.
enum ShellIntegrationEvent: Sendable {
    /// OSC 133;A — prompt mark (prompt is about to be drawn)
    case promptStarted
    /// OSC 133;B — command start mark (user begins typing)
    case commandStarted
    /// OSC 133;C — execution start mark (command submitted to shell)
    case executionStarted
    /// OSC 133;D[;exitCode] — execution finished, optional exit code
    case executionFinished(exitCode: Int?)
}

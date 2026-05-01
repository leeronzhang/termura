import Foundation

/// Events emitted when OSC 133 sequences are parsed from terminal output.
/// Each value maps to a specific shell integration marker.
enum ShellIntegrationEvent: Sendable, Equatable {
    /// OSC 133;A — prompt mark (prompt is about to be drawn)
    case promptStarted
    /// OSC 133;B — command start mark (user begins typing)
    case commandStarted
    /// OSC 133;C — execution start mark (command submitted to shell)
    case executionStarted
    /// OSC 133;D[;exitCode] — execution finished, optional exit code
    case executionFinished(exitCode: Int?)
    /// OSC 133;X;key=value;key=value... — Termura private extension carrying
    /// arbitrary metadata that gets attached to the next command's chunk.
    /// `PTYCommandBridge` (remote control) used to inject these markers but
    /// stopped because the `printf` source line was visible to the user via
    /// shell echo on every command; today the field stays for any
    /// user-installed shell-integration script that wants to publish its
    /// own key=value pairs.
    case commandMetadata([String: String])
}

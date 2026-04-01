import Foundation

/// Events emitted by a terminal engine to its consumers.
enum TerminalOutputEvent: Sendable {
    /// Raw bytes received from the PTY.
    case data(Data)
    /// The PTY process exited with the given code.
    case processExited(Int32)
    /// The terminal title changed (via OSC 0/2).
    case titleChanged(String)
    /// Working directory changed (via OSC 7).
    case workingDirectoryChanged(String)
}

import Foundation

/// Value type snapshot of live session metrics for display in the metadata bar.
struct SessionMetadata: Sendable {
    let sessionID: SessionID
    /// Heuristic token estimate (chars / 4).
    var estimatedTokenCount: Int
    /// Total characters accumulated this session.
    var totalCharacterCount: Int
    /// Elapsed time since session start.
    var sessionDuration: TimeInterval
    /// Number of commands executed.
    var commandCount: Int
    /// Current working directory.
    var workingDirectory: String

    // MARK: - Factory

    static func empty(sessionID: SessionID, workingDirectory: String) -> SessionMetadata {
        SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: 0,
            totalCharacterCount: 0,
            sessionDuration: 0,
            commandCount: 0,
            workingDirectory: workingDirectory
        )
    }
}

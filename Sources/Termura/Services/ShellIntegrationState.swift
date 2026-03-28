import Foundation

// MARK: - Phase

/// Finite state machine phases for tracking shell command lifecycle.
enum ShellIntegrationPhase: Sendable {
    case idle
    case promptActive
    case commandInput(String)
    case executing(command: String, startedAt: Date)
}

// MARK: - State

/// Pure value type FSM. All transitions are driven by `apply(_:)`.
/// Invalid transitions are silently ignored — no crashes.
struct ShellIntegrationState: Sendable {
    private(set) var phase: ShellIntegrationPhase = .idle

    // MARK: - Transitions

    /// Apply a shell integration event, advancing the FSM.
    /// - Parameter now: Current timestamp for execution start. Defaults to `Date()` for
    ///   production use; inject a fixed value in tests for deterministic assertions.
    mutating func apply(_ event: ShellIntegrationEvent, now: Date = Date()) {
        switch (phase, event) {
        case (.idle, .promptStarted),
             (.executing, .promptStarted):
            phase = .promptActive

        case (.promptActive, .commandStarted):
            phase = .commandInput("")

        case let (.commandInput(cmd), .executionStarted):
            phase = .executing(command: cmd, startedAt: now)

        case (.executing, .executionFinished):
            phase = .idle

        // Allow prompt to restart from promptActive for chained commands
        case (.promptActive, .promptStarted):
            phase = .promptActive

        default:
            // Invalid transition — silently ignore
            break
        }
    }

    // MARK: - Accessors

    var currentCommand: String? {
        if case let .commandInput(cmd) = phase { return cmd }
        if case let .executing(cmd, _) = phase { return cmd }
        return nil
    }

    var executionStartTime: Date? {
        if case let .executing(_, startedAt) = phase { return startedAt }
        return nil
    }
}

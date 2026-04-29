import Foundation

// Closures captured by `LiveRemoteSessionsAdapter` resolve the active project
// state through these helpers. They live in their own extension to keep
// `AppDelegate.swift` under the 250-line soft cap and to make the boundary
// between "Composition Root wiring" and "Remote-control bridge logic" explicit.
extension AppDelegate {
    @MainActor
    static func gatherActiveSessions(coordinator: ProjectCoordinator?) -> [RemoteSessionInfo] {
        guard let scope = coordinator?.activeContext?.sessionScope else { return [] }
        return scope.store.sessions.map { record in
            RemoteSessionInfo(
                id: record.id.rawValue,
                title: record.title,
                workingDirectory: record.workingDirectory,
                lastActivityAt: record.lastActiveAt
            )
        }
    }

    @MainActor
    static func runRemoteCommand(
        coordinator: ProjectCoordinator?,
        line: String,
        sessionId: UUID
    ) async throws -> CommandRunResult {
        guard let context = coordinator?.activeContext else {
            throw RemoteAdapterError.noActiveProject
        }
        let id = SessionID(rawValue: sessionId)
        do {
            let outcome = try await PTYCommandBridge.run(
                line: line,
                sessionId: id,
                commandId: UUID(),
                scope: context.sessionScope,
                commandRouter: context.commandRouter
            )
            if outcome.isSentinelMatched {
                return CommandRunResult(stdout: outcome.stdout, exitCode: outcome.exitCode)
            }
            // Sentinel was not echoed back within the timeout (shells stripping
            // OSC, non-interactive shells, vim/repl modes). Fall back to a
            // user-facing notice so the remote client still sees progress.
            let fallback = "Command dispatched, but PTY output capture timed out. " +
                "Check the Mac terminal for live output."
            return CommandRunResult(stdout: fallback, exitCode: outcome.exitCode)
        } catch PTYCommandBridge.Failure.sessionNotFound {
            throw RemoteAdapterError.sessionNotFound
        } catch PTYCommandBridge.Failure.noActiveProject {
            throw RemoteAdapterError.noActiveProject
        }
    }
}

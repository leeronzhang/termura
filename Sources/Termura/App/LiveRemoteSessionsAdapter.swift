// Adapter implementation in the main module — bridges the public `RemoteSessionsAdapter`
// protocol (defined in `RemoteIntegration+Stub.swift`) to the @MainActor `SessionStore`.
//
// Constructed once in `AppDelegate` with closures that capture the active project state.
// `Sendable` is satisfied because the closures themselves are `@Sendable @MainActor`.

import Foundation

struct LiveRemoteSessionsAdapter: RemoteSessionsAdapter {
    typealias ListProvider = @Sendable @MainActor () -> [RemoteSessionInfo]
    typealias CommandRunner = @Sendable @MainActor (String, UUID) async throws -> CommandRunResult

    let listProvider: ListProvider
    let commandRunner: CommandRunner

    func listSessions() async -> [RemoteSessionInfo] {
        await listProvider()
    }

    func executeCommand(line: String, sessionId: UUID) async throws -> CommandRunResult {
        try await commandRunner(line, sessionId)
    }
}

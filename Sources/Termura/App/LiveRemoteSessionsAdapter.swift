// Adapter implementation in the main module — bridges the public `RemoteSessionsAdapter`
// protocol (defined in `RemoteIntegration+Stub.swift`) to the @MainActor `SessionStore`.
//
// Constructed once in `AppDelegate` with closures that capture the active project state.
// `Sendable` is satisfied because the closures themselves are `@Sendable @MainActor`
// and `AsyncStream<Void>` is itself Sendable.
//
// `changeStream` is the push-on-change seam consumed by the harness router so iOS
// learns about session opens/closes immediately instead of hanging on the snapshot
// it pulled at pair time. `SessionListBroadcaster` (composition root) yields into
// the paired `AsyncStream<Void>.Continuation`. Single-consumer by design — the
// harness router subscribes once per `start()`.

import Foundation

struct LiveRemoteSessionsAdapter: RemoteSessionsAdapter {
    typealias ListProvider = @Sendable @MainActor () -> [RemoteSessionInfo]
    typealias CommandRunner = @Sendable @MainActor (String, UUID) async throws -> CommandRunResult

    let listProvider: ListProvider
    let commandRunner: CommandRunner
    private let changeStream: AsyncStream<Void>

    init(
        listProvider: @escaping ListProvider,
        commandRunner: @escaping CommandRunner,
        changeStream: AsyncStream<Void>
    ) {
        self.listProvider = listProvider
        self.commandRunner = commandRunner
        self.changeStream = changeStream
    }

    func listSessions() async -> [RemoteSessionInfo] {
        await listProvider()
    }

    func executeCommand(line: String, sessionId: UUID) async throws -> CommandRunResult {
        try await commandRunner(line, sessionId)
    }

    func sessionListChanges() -> AsyncStream<Void> {
        changeStream
    }
}

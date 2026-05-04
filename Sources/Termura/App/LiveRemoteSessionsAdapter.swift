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
import TermuraRemoteProtocol

struct LiveRemoteSessionsAdapter: RemoteSessionsAdapter {
    typealias ListProvider = @Sendable @MainActor () -> [RemoteSessionInfo]
    typealias CommandRunner = @Sendable @MainActor (String, UUID) async throws -> CommandRunResult
    typealias ScreenCapturer = @Sendable @MainActor (UUID) -> ScreenFramePayload?
    typealias PtySubscriber = @Sendable @MainActor (UUID) async -> PtyByteTap.Subscription?
    typealias PtyUnsubscriber = @Sendable @MainActor (UUID, UUID) async -> Void
    typealias CheckpointProvider = @Sendable @MainActor (UUID, UInt64) -> PtyStreamCheckpoint?
    typealias PtyResizer = @Sendable @MainActor (UUID, Int, Int) async -> Bool
    typealias AgentEventSubscriber = @Sendable @MainActor (UUID, UUID?) async -> AgentEventSubscription?
    typealias AgentEventUnsubscriber = @Sendable @MainActor (UUID, UUID) async -> Void

    let listProvider: ListProvider
    let commandRunner: CommandRunner
    private let changeStream: AsyncStream<Void>
    let screenCapturer: ScreenCapturer
    let ptySubscriber: PtySubscriber
    let ptyUnsubscriber: PtyUnsubscriber
    let checkpointProvider: CheckpointProvider
    let ptyResizer: PtyResizer
    let agentEventSubscriber: AgentEventSubscriber
    let agentEventUnsubscriber: AgentEventUnsubscriber

    init(
        listProvider: @escaping ListProvider,
        commandRunner: @escaping CommandRunner,
        changeStream: AsyncStream<Void>,
        screenCapturer: @escaping ScreenCapturer,
        ptySubscriber: @escaping PtySubscriber,
        ptyUnsubscriber: @escaping PtyUnsubscriber,
        checkpointProvider: @escaping CheckpointProvider,
        ptyResizer: @escaping PtyResizer,
        agentEventSubscriber: @escaping AgentEventSubscriber,
        agentEventUnsubscriber: @escaping AgentEventUnsubscriber
    ) {
        self.listProvider = listProvider
        self.commandRunner = commandRunner
        self.changeStream = changeStream
        self.screenCapturer = screenCapturer
        self.ptySubscriber = ptySubscriber
        self.ptyUnsubscriber = ptyUnsubscriber
        self.checkpointProvider = checkpointProvider
        self.ptyResizer = ptyResizer
        self.agentEventSubscriber = agentEventSubscriber
        self.agentEventUnsubscriber = agentEventUnsubscriber
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

    func captureScreen(sessionId: UUID) async -> ScreenFramePayload? {
        await screenCapturer(sessionId)
    }

    func subscribePty(sessionId: UUID) async -> PtyByteTap.Subscription? {
        await ptySubscriber(sessionId)
    }

    func unsubscribePty(sessionId: UUID, subscriptionId: UUID) async {
        await ptyUnsubscriber(sessionId, subscriptionId)
    }

    func currentCheckpoint(sessionId: UUID, seq: UInt64) async -> PtyStreamCheckpoint? {
        await checkpointProvider(sessionId, seq)
    }

    func resizePty(sessionId: UUID, cols: Int, rows: Int) async -> Bool {
        await ptyResizer(sessionId, cols, rows)
    }

    func subscribeAgentEvents(
        sessionId: UUID,
        sinceEventId: UUID?
    ) async -> AgentEventSubscription? {
        await agentEventSubscriber(sessionId, sinceEventId)
    }

    func unsubscribeAgentEvents(sessionId: UUID, subscriptionId: UUID) async {
        await agentEventUnsubscriber(sessionId, subscriptionId)
    }
}

import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectCoordinator")

// MARK: - Termination handoff & flush

extension ProjectCoordinator {
    /// - Parameter metricsFlush: Optional additional async work (e.g. metrics persistence) to include
    ///   in the structured task group so it is protected by the termination timeout.
    ///   `MetricsPersistenceService` is an actor (Sendable) — safe to capture in @Sendable closure.
    func handleTermination(
        metricsFlush: (@Sendable () async -> Void)? = nil
    ) -> NSApplication.TerminateReply {
        let contexts = projectWindows.values.map(\.projectContext)
        guard !contexts.isEmpty else { return .terminateNow }
        scheduleTerminationFlush(contexts: contexts, metricsFlush: metricsFlush)
        return .terminateLater
    }

    /// Races flush+handoff against a deadline so a hung DB never blocks `reply(toApplicationShouldTerminate:)`.
    private func scheduleTerminationFlush(
        contexts: [ProjectContext],
        metricsFlush: (@Sendable () async -> Void)?
    ) {
        // WHY: App termination must keep flush + handoff off MainActor while honoring a bounded shutdown path.
        // OWNER: ProjectCoordinator owns this detached termination task via the app termination lifecycle.
        // TEARDOWN: The surrounding termination reply path completes when this detached task finishes or times out.
        // TEST: Cover successful flush, timeout fallback, and app-termination reply semantics.
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    if let flush = metricsFlush {
                        await flush()
                    }
                    for ctx in contexts {
                        await ctx.flushPendingWrites()
                    }
                    let items = await MainActor.run {
                        contexts.compactMap { $0.makeTerminationHandoffItem() }
                    }
                    for item in items {
                        do {
                            try await item.handoff.generateHandoff(
                                session: item.session,
                                chunks: item.chunks,
                                agentState: item.agentState,
                                projectRoot: item.projectRoot
                            )
                        } catch {
                            logger.error("generateHandoff failed on termination: \(error)")
                        }
                    }
                }
                group.addTask {
                    do {
                        try await Task.sleep(for: .seconds(AppConfig.Runtime.terminationFlushTimeoutSeconds))
                        // Only reached when the deadline fires before work completes.
                        logger.warning("Termination flush deadline exceeded — replying anyway")
                    } catch {
                        // CancellationError: work task finished first — normal fast path.
                        logger.debug("Termination deadline cancelled (work completed on time)")
                    }
                }
                _ = await group.next() // first child to finish (work or timeout) wins
            }
            Task { @MainActor in NSApp.reply(toApplicationShouldTerminate: true) }
        }
    }
}

@MainActor
private extension ProjectContext {
    func makeTerminationHandoffItem() -> TerminationHandoffItem? {
        guard let activeID = sessionScope.store.activeSessionID,
              let session = sessionScope.store.session(id: activeID) else {
            return nil
        }
        let chunks = viewStateManager.outputStores[activeID].map { Array($0.chunks) } ?? []
        let agentState = sessionScope.agentStates.agents[activeID]
            ?? AgentState(sessionID: activeID, agentType: .unknown)
        return TerminationHandoffItem(
            handoff: sessionHandoffService,
            session: session,
            chunks: chunks,
            agentState: agentState,
            projectRoot: projectURL.path
        )
    }
}

private struct TerminationHandoffItem {
    let handoff: any SessionHandoffServiceProtocol
    let session: SessionRecord
    let chunks: [OutputChunk]
    let agentState: AgentState
    let projectRoot: String
}

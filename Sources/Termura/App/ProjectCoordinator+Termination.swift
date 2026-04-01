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
        let handoffItems = collectHandoffItems()
        // Even without handoff items, flush pending writes to DB before exiting.
        guard !handoffItems.isEmpty || !contexts.isEmpty else { return .terminateNow }
        scheduleTerminationFlush(contexts: contexts, items: handoffItems, metricsFlush: metricsFlush)
        return .terminateLater
    }

    private func collectHandoffItems() -> [TerminationHandoffItem] {
        projectWindows.values.compactMap { controller in
            let ctx = controller.projectContext
            guard let activeID = ctx.sessionScope.store.activeSessionID,
                  let session = ctx.sessionScope.store.session(id: activeID) else {
                return nil
            }
            let chunks = ctx.viewStateManager.outputStores[activeID].map { Array($0.chunks) } ?? []
            let agentState = ctx.sessionScope.agentStates.agents[activeID]
                ?? AgentState(sessionID: activeID, agentType: .unknown)
            return TerminationHandoffItem(
                handoff: ctx.sessionHandoffService,
                session: session,
                chunks: chunks,
                agentState: agentState,
                projectRoot: ctx.projectURL.path
            )
        }
    }

    /// Races flush+handoff against a deadline so a hung DB never blocks `reply(toApplicationShouldTerminate:)`.
    private func scheduleTerminationFlush(
        contexts: [ProjectContext],
        items: [TerminationHandoffItem],
        metricsFlush: (@Sendable () async -> Void)?
    ) {
        Task.detached {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    if let flush = metricsFlush { await flush() }
                    for ctx in contexts { await ctx.flushPendingWrites() }
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

private struct TerminationHandoffItem {
    let handoff: any SessionHandoffServiceProtocol
    let session: SessionRecord
    let chunks: [OutputChunk]
    let agentState: AgentState
    let projectRoot: String
}

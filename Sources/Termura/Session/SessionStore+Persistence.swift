import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore+Persistence")

// MARK: - Session Tree & Persistence

extension SessionStore {
    // MARK: - Session Tree

    func createBranch(from sessionID: SessionID, type: BranchType, title: String? = nil) async {
        let repo = repository
        let resolvedTitle = title ?? "\(type.rawValue.capitalized) branch"
        do {
            let branch = try await repo.createBranch(from: sessionID, type: type, title: resolvedTitle)
            appendSession(branch)
            ensureEngine(for: branch.id)
            activeSessionID = branch.id
            errorMessage = nil
            logger.info("Created branch \(branch.id) from \(sessionID)")
        } catch {
            errorMessage = "Failed to create branch: \(error.localizedDescription)"
            logger.error("Failed to create branch: \(error)")
        }
    }

    /// Merge a branch summary back to the parent session.
    func mergeBranchSummary(
        branchID: SessionID,
        summary: String,
        messageRepo: (any SessionMessageRepositoryProtocol)?
    ) async {
        guard let idx = sessionIndex[branchID],
              let parentID = sessions[idx].parentID else { return }
        let repo = repository

        do {
            try await repo.updateSummary(branchID, summary: summary)
            mutateSession(id: branchID) { $0.summary = summary }

            if let msgRepo = messageRepo {
                let msg = BranchSummarizer.createSummaryMessage(
                    summary: summary,
                    branchSessionID: branchID,
                    parentSessionID: parentID
                )
                try await msgRepo.save(msg)
            }

            activeSessionID = parentID
            errorMessage = nil
            logger.info("Merged branch \(branchID) summary to parent \(parentID)")
        } catch {
            errorMessage = "Failed to merge branch: \(error.localizedDescription)"
            logger.error("Failed to merge branch summary: \(error)")
        }
    }

    func navigateToParent(of sessionID: SessionID) {
        guard let idx = sessionIndex[sessionID],
              let parentID = sessions[idx].parentID,
              sessionIndex[parentID] != nil else {
            return
        }
        activeSessionID = parentID
    }

    // MARK: - Tracked persistence helpers

    /// Awaits all in-flight persistence Tasks and force-saves current in-memory
    /// state to capture any debounced changes not yet written to DB.
    /// Call during app termination or project close.
    func flushPendingWrites() async {
        // 1. Cancel all per-operation debounce timers — force-save below covers them.
        taskCoordinator.cancelAllPending()

        // 2. Await all tracked writes so prior mutations land in DB.
        await taskCoordinator.flushTracked()

        // 3. Force-save every session to capture debounced changes
        //    (rename, workingDirectory) that may not have been flushed yet.
        for session in sessions {
            do {
                try await repository.save(session)
            } catch {
                state = .error("Failed to save session: \(error.localizedDescription)")
                logger.error("Flush save error for session \(session.id): \(error)")
            }
        }
    }

    /// Waits until debounced persistence and tracked write tasks have both drained.
    /// Useful in tests so they can assert on repository state without fixed sleeps.
    func waitForPersistenceIdle() async {
        await taskCoordinator.waitForIdle()
    }

    /// Waits until both engine activation debounce and persistence work have settled.
    func waitForIdle() async {
        await waitForEngineActivationIdle()
        await waitForPersistenceIdle()
    }

    /// Persists an operation asynchronously while tracking the Task so it can
    /// be awaited during `flushPendingWrites()`.
    func persistTracked(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void,
        onFailure: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let repo = repository
        taskCoordinator.track(operation: {
            try await operation(repo)
        }, onFailure: { [weak self] error in
            self?.state = .error("Failed to save session: \(error.localizedDescription)")
            logger.error("Persistence error: \(error)")
            onFailure?()
        })
    }

    /// Debounces a persistence operation under a named `key`.
    func scheduleDebounced(
        key: String,
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        let repo = repository
        taskCoordinator.debounce(
            key: key,
            delay: AppConfig.Runtime.sessionMetadataDebounce,
            clock: clock,
            operation: {
                try await operation(repo)
            },
            onFailure: { [weak self] error in
                self?.state = .error("Failed to save session: \(error.localizedDescription)")
                logger.error("Debounced save error: \(error)")
            }
        )
    }
}

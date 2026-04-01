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
            engineStore.createEngine(for: branch.id, shell: defaultShell, currentDirectory: projectRoot)
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
        // Also cancel the engine-creation debounce; no new PTY forks during teardown.
        engineEnsureTask?.cancel()
        engineEnsureTask = nil
        for task in debounceTasks.values { task.cancel() }
        debounceTasks.removeAll()

        // 2. Await all tracked writes so prior mutations land in DB.
        let snapshot = Array(pendingWrites.values)
        pendingWrites.removeAll()
        for task in snapshot {
            await task.value
        }

        // 3. Force-save every session to capture debounced changes
        //    (rename, workingDirectory) that may not have been flushed yet.
        for session in sessions {
            do {
                try await repository.save(session)
            } catch {
                errorMessage = "Failed to save session: \(error.localizedDescription)"
                logger.error("Flush save error for session \(session.id): \(error)")
            }
        }
    }

    /// Persists an operation asynchronously while tracking the Task so it can
    /// be awaited during `flushPendingWrites()`.
    ///
    /// `onFailure` is an optional rollback closure called on `@MainActor` when the
    /// DB write throws. Use it to revert optimistic in-memory mutations so the UI
    /// stays consistent with what is actually persisted.
    func persistTracked(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void,
        onFailure: (@MainActor @Sendable () -> Void)? = nil
    ) {
        let repo = repository
        let id = UUID()
        let task = Task { [weak self] in
            defer { self?.pendingWrites.removeValue(forKey: id) }
            do {
                try await operation(repo)
            } catch {
                self?.errorMessage = "Failed to save session: \(error.localizedDescription)"
                logger.error("Persistence error: \(error)")
                onFailure?()
            }
        }
        pendingWrites[id] = task
    }

    /// Debounces a persistence operation under a named `key`.
    /// Each unique key has its own cancellation slot, so concurrent operations
    /// (e.g. rename and workingDirectory update for the same session) do not
    /// cancel each other. Use the pattern `"<operation>-\(id)"` for keys.
    func scheduleDebounced(
        key: String,
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        let repo = repository
        debounceTasks[key]?.cancel()
        debounceTasks[key] = Task { [weak self] in
            do {
                guard let self else { return }
                try await self.clock.sleep(for: AppConfig.Runtime.sessionMetadataDebounce)
                guard !Task.isCancelled else { return }
                try await operation(repo)
            } catch is CancellationError {
                // CancellationError is expected — a newer save supersedes this one.
                return
            } catch {
                self?.errorMessage = "Failed to save session: \(error.localizedDescription)"
                logger.error("Debounced save error: \(error)")
            }
        }
    }
}

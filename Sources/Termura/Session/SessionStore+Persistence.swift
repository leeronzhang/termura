import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore+Persistence")

// MARK: - Session Tree & Persistence

extension SessionStore {
    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String = "") async -> SessionRecord? {
        guard let repo = repository else {
            logger.warning("Cannot create branch without repository")
            return nil
        }
        let resolvedTitle = title.isEmpty ? "\(type.rawValue.capitalized) branch" : title
        do {
            let branch = try await repo.createBranch(from: sessionID, type: type, title: resolvedTitle)
            sessions.append(branch)
            engineStore.createEngine(for: branch.id, shell: defaultShell)
            activeSessionID = branch.id
            errorMessage = nil
            logger.info("Created branch \(branch.id) from \(sessionID)")
            return branch
        } catch {
            errorMessage = "Failed to create branch: \(error.localizedDescription)"
            logger.error("Failed to create branch: \(error)")
            return nil
        }
    }

    /// Merge a branch summary back to the parent session.
    func mergeBranchSummary(
        branchID: SessionID,
        summary: String,
        messageRepo: (any SessionMessageRepositoryProtocol)?
    ) async {
        guard let repo = repository,
              let idx = sessions.firstIndex(where: { $0.id == branchID }),
              let parentID = sessions[idx].parentID else { return }

        do {
            try await repo.updateSummary(branchID, summary: summary)
            sessions[idx].summary = summary

            if let msgRepo = messageRepo {
                let summarizer = BranchSummarizer()
                let msg = await summarizer.createSummaryMessage(
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
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[idx].parentID,
              sessions.contains(where: { $0.id == parentID }) else {
            return
        }
        activeSessionID = parentID
    }

    // MARK: - Flush

    /// Awaits all in-flight persistence Tasks and force-saves current in-memory
    /// state to capture any debounced changes not yet written to DB.
    /// Call during app termination or project close.
    func flushPendingWrites() async {
        guard let repo = repository else { return }

        // 1. Cancel debounce timer — we will persist everything directly.
        saveTask?.cancel()
        saveTask = nil

        // 2. Await all tracked writes so prior mutations land in DB.
        let snapshot = pendingWrites
        pendingWrites.removeAll()
        for task in snapshot {
            await task.value
        }

        // 3. Force-save every session to capture debounced changes
        //    (rename, workingDirectory) that may not have been flushed yet.
        for session in sessions {
            do {
                try await repo.save(session)
            } catch {
                logger.error("Flush save error for session \(session.id): \(error)")
            }
        }
    }

    // MARK: - Tracked persistence helpers

    /// Persists an operation asynchronously while tracking the Task so it can
    /// be awaited during `flushPendingWrites()`.
    func persistTracked(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        guard let repo = repository else { return }
        let task = Task {
            do {
                try await operation(repo)
            } catch {
                logger.error("Persistence error: \(error)")
            }
        }
        pendingWrites.append(task)
    }

    func scheduleDebounced(
        _ operation: @Sendable @escaping (any SessionRepositoryProtocol) async throws -> Void
    ) {
        guard let repo = repository else { return }
        saveTask?.cancel()
        saveTask = Task {
            do {
                try await clock.sleep(for: .seconds(AppConfig.Runtime.notesAutoSaveSeconds))
                guard !Task.isCancelled else { return }
                try await operation(repo)
            } catch is CancellationError {
                return
            } catch {
                logger.error("Debounced save error: \(error)")
            }
        }
    }
}

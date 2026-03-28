import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore+Persistence")

// MARK: - Session Tree & Persistence

extension SessionStore {
    // MARK: - Session Tree

    @discardableResult
    func createBranch(from sessionID: SessionID, type: BranchType, title: String? = nil) async -> SessionRecord? {
        guard let repo = repository else {
            logger.warning("Cannot create branch without repository")
            return nil
        }
        let resolvedTitle = title ?? "\(type.rawValue.capitalized) branch"
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
        guard let idx = sessions.firstIndex(where: { $0.id == sessionID }),
              let parentID = sessions[idx].parentID,
              sessions.contains(where: { $0.id == parentID }) else {
            return
        }
        activeSessionID = parentID
    }

}

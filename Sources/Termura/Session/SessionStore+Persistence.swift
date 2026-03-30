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
            engineStore.createEngine(for: branch.id, shell: defaultShell)
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

}

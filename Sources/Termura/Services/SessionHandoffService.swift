import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionHandoffService")

// MARK: - Models

struct DecisionEntry: Sendable {
    let timestamp: Date
    let summary: String
}

struct HandoffContext: Sendable {
    var taskStatus: String
    var decisions: [DecisionEntry]
    var errors: [String]
    var agentType: AgentType?
    var sessionDuration: TimeInterval
    var lastUpdated: Date
}

private struct HandoffPayload: Encodable {
    let agentType: String
    let decisionsCount: Int
}

// MARK: - Service

actor SessionHandoffService: SessionHandoffServiceProtocol {
    private let messageRepo: any SessionMessageRepositoryProtocol
    private let harnessEventRepo: any HarnessEventRepositoryProtocol
    private let fileManager: any FileManagerProtocol
    let clock: any AppClock

    init(
        messageRepo: any SessionMessageRepositoryProtocol,
        harnessEventRepo: any HarnessEventRepositoryProtocol,
        fileManager: any FileManagerProtocol = FileManager.default,
        clock: any AppClock = LiveClock()
    ) {
        self.messageRepo = messageRepo
        self.harnessEventRepo = harnessEventRepo
        self.fileManager = fileManager
        self.clock = clock
    }

    // MARK: - Public

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState,
        projectRoot: String
    ) async throws {
        guard !projectRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            logger.debug("Skipping session handoff for \(session.id): empty project root")
            return
        }
        let context = await buildHandoffContext(
            session: session,
            chunks: chunks,
            agentState: agentState,
            projectRoot: projectRoot
        )

        try await persistHandoff(
            context: context,
            session: session,
            projectRoot: projectRoot
        )

        logger.info("Session handoff generated for \(session.id) at \(projectRoot)")
    }

    // MARK: - Private Helpers

    private func buildHandoffContext(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState,
        projectRoot: String
    ) async -> HandoffContext {
        let summary = BranchSummarizer.summarize(
            chunks: chunks,
            branchType: session.branchType
        )
        let truncatedSummary = String(
            summary.prefix(AppConfig.SessionHandoff.maxSummaryLength)
        )

        let decisions = extractDecisions(from: chunks)
        let errors = extractErrors(from: chunks)
        let duration = session.lastActiveAt.timeIntervalSince(session.createdAt)

        let existing = await readExistingContext(projectRoot: projectRoot)

        var mergedDecisions = (existing?.decisions ?? []) + decisions
        if mergedDecisions.count > AppConfig.SessionHandoff.maxDecisionEntries {
            mergedDecisions = Array(
                mergedDecisions.suffix(AppConfig.SessionHandoff.maxDecisionEntries)
            )
        }

        return HandoffContext(
            taskStatus: truncatedSummary,
            decisions: mergedDecisions,
            errors: errors,
            agentType: agentState.agentType,
            sessionDuration: duration,
            lastUpdated: clock.now()
        )
    }

    private func persistHandoff(
        context: HandoffContext,
        session: SessionRecord,
        projectRoot: String
    ) async throws {
        try await writeContextFile(context: context, projectRoot: projectRoot)

        let path = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName).path
        let message = SessionMessage(
            sessionID: session.id,
            role: .system,
            contentType: .metadata,
            content: "[Session Handoff] Context written to \(path)"
        )
        try await messageRepo.save(message)

        let payloadData = try JSONEncoder().encode(HandoffPayload(
            agentType: context.agentType?.rawValue ?? "unknown",
            decisionsCount: context.decisions.count
        ))
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        let event = HarnessEvent(
            sessionID: session.id,
            eventType: .sessionHandoff,
            payload: payloadString
        )
        try await harnessEventRepo.save(event)
    }

    func readExistingContext(projectRoot: String) async -> HandoffContext? {
        let fileURL = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            // Non-critical: first handoff for this project, no prior context to merge.
            return nil
        }
        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            // File exists but cannot be read — infrastructure failure (permission, I/O error).
            // Log as error, not debug, so the problem is observable.
            logger.error("Failed to read existing context file at \(fileURL.path): \(error.localizedDescription)")
            return nil
        }
        return parseContextMarkdown(content)
    }

    // MARK: - File I/O

    private func writeContextFile(
        context: HandoffContext,
        projectRoot: String
    ) async throws {
        let rootURL = URL(fileURLWithPath: projectRoot)
        let dirPath = rootURL.appendingPathComponent(AppConfig.SessionHandoff.directoryName).path
        let filePath = rootURL
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName).path
        let markdown = renderContextMarkdown(context)
        // Capture the injected instance before crossing into the detached task so
        // that tests can substitute a mock without the task falling back to the real FS.
        let fm = fileManager

        // WHY: Handoff persistence performs directory creation and file writes off the caller's actor.
        // OWNER: generateHandoff owns this detached write and awaits it inline.
        // TEARDOWN: Awaiting .value ensures the write completes before generateHandoff returns.
        // TEST: Cover gitignore repair, directory creation, and handoff file persistence.
        try await Task.detached {
            // Ensure .termura/ is in .gitignore before creating the directory,
            // preventing accidental commit of AI session data.
            ensureProjectGitignore(at: rootURL, fileManager: fm)
            // Ensure directory exists
            if !fm.fileExists(atPath: dirPath) {
                try fm.createDirectory(
                    atPath: dirPath,
                    withIntermediateDirectories: true
                )
            }

            // Backup existing file before overwrite
            let backupPath = filePath + ".backup"
            var backedUp = false
            if fm.fileExists(atPath: filePath) {
                let existing = try String(contentsOfFile: filePath, encoding: .utf8)
                try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
                backedUp = true
            }

            try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)

            // Clean up backup only after successful write
            if backedUp {
                do {
                    try fm.removeItem(atPath: backupPath)
                } catch {
                    logger.warning("Failed to remove backup at \(backupPath): \(error.localizedDescription)")
                }
            }
        }.value
    }
}

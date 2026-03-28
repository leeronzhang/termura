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

// MARK: - Service

actor SessionHandoffService: SessionHandoffServiceProtocol {
    private let messageRepo: any SessionMessageRepositoryProtocol
    private let harnessEventRepo: any HarnessEventRepositoryProtocol
    private let fileManager: FileManager

    /// Keywords used to identify error lines when summarising output chunks.
    /// Checked case-insensitively against lowercased line content.
    private static let errorLineKeywords: [String] = [
        "error", "fatal", "traceback", "panic", "failed"
    ]

    init(
        messageRepo: any SessionMessageRepositoryProtocol,
        harnessEventRepo: any HarnessEventRepositoryProtocol,
        fileManager: FileManager = .default
    ) {
        self.messageRepo = messageRepo
        self.harnessEventRepo = harnessEventRepo
        self.fileManager = fileManager
    }

    // MARK: - Public

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState
    ) async throws {
        guard let projectRoot = session.workingDirectory else { return }

        let context = await buildHandoffContext(
            session: session,
            chunks: chunks,
            agentState: agentState
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
        agentState: AgentState
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

        let existing: HandoffContext? = if let dir = session.workingDirectory {
            await readExistingContext(projectRoot: dir)
        } else {
            nil
        }

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
            lastUpdated: Date()
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

        let event = HarnessEvent(
            sessionID: session.id,
            eventType: .sessionHandoff,
            payload: "{\"agentType\":\"\(context.agentType?.rawValue ?? "unknown")\",\"decisionsCount\":\(context.decisions.count)}"
        )
        try await harnessEventRepo.save(event)
    }

    func readExistingContext(projectRoot: String) async -> HandoffContext? {
        let filePath = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName).path
        let content: String?
        do {
            content = try String(contentsOfFile: filePath, encoding: .utf8)
        } catch {
            // Non-critical: missing context file is expected on first handoff — returns nil.
            logger.debug("No existing context file at \(filePath): \(error.localizedDescription)")
            content = nil
        }
        guard let content else { return nil }
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
        let fm = FileManager.default

        try await Task.detached {
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
                    // Non-critical: stale backup is harmless and will be overwritten next time.
                    logger.warning("Failed to remove backup at \(backupPath): \(error.localizedDescription)")
                }
            }
        }.value
    }

    // MARK: - Extraction Heuristics

    private func extractDecisions(from chunks: [OutputChunk]) -> [DecisionEntry] {
        let decisionKeywords = [
            "chose", "decided", "because", "instead of",
            "switched to", "going with", "picked", "selected"
        ]
        var entries: [DecisionEntry] = []

        for chunk in chunks {
            for line in chunk.outputLines {
                let lower = line.lowercased()
                let matches = decisionKeywords.contains { lower.contains($0) }
                if matches {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, trimmed.count > 10 else { continue }
                    let entry = DecisionEntry(
                        timestamp: chunk.startedAt,
                        summary: String(trimmed.prefix(200))
                    )
                    entries.append(entry)
                }
            }
        }

        return Array(entries.prefix(10))
    }

    private func extractErrors(from chunks: [OutputChunk]) -> [String] {
        var errors: [String] = []

        for chunk in chunks where chunk.contentType == .error || (chunk.exitCode ?? 0) != 0 {
            for line in chunk.outputLines.prefix(5) {
                let lower = line.lowercased()
                let isError = Self.errorLineKeywords.contains(where: lower.contains)
                if isError {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    errors.append(String(trimmed.prefix(200)))
                }
            }
        }

        return Array(errors.prefix(10))
    }
}

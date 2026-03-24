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

actor SessionHandoffService {
    private let messageRepo: any SessionMessageRepositoryProtocol
    private let harnessEventRepo: any HarnessEventRepositoryProtocol
    private let summarizer: BranchSummarizer
    private let fileManager: FileManager

    init(
        messageRepo: any SessionMessageRepositoryProtocol,
        harnessEventRepo: any HarnessEventRepositoryProtocol,
        summarizer: BranchSummarizer,
        fileManager: FileManager = .default
    ) {
        self.messageRepo = messageRepo
        self.harnessEventRepo = harnessEventRepo
        self.summarizer = summarizer
        self.fileManager = fileManager
    }

    // MARK: - Public

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState
    ) async throws {
        let projectRoot = session.workingDirectory
        guard !projectRoot.isEmpty else { return }

        let summary = await summarizer.summarize(
            chunks: chunks,
            branchType: session.branchType
        )
        let truncatedSummary = String(
            summary.prefix(AppConfig.SessionHandoff.maxSummaryLength)
        )

        let decisions = extractDecisions(from: chunks)
        let errors = extractErrors(from: chunks)
        let duration = session.lastActiveAt.timeIntervalSince(session.createdAt)

        let existing = readExistingContext(projectRoot: projectRoot)

        var mergedDecisions = (existing?.decisions ?? []) + decisions
        if mergedDecisions.count > AppConfig.SessionHandoff.maxDecisionEntries {
            mergedDecisions = Array(
                mergedDecisions.suffix(AppConfig.SessionHandoff.maxDecisionEntries)
            )
        }

        let context = HandoffContext(
            taskStatus: truncatedSummary,
            decisions: mergedDecisions,
            errors: errors,
            agentType: agentState.agentType,
            sessionDuration: duration,
            lastUpdated: Date()
        )

        try writeContextFile(context: context, projectRoot: projectRoot)

        // Record metadata message
        let path = "\(projectRoot)/\(AppConfig.SessionHandoff.directoryName)/\(AppConfig.SessionHandoff.contextFileName)"
        let message = SessionMessage(
            sessionID: session.id,
            role: .system,
            contentType: .metadata,
            content: "[Session Handoff] Context written to \(path)"
        )
        try await messageRepo.save(message)

        // Record harness event
        let event = HarnessEvent(
            sessionID: session.id,
            eventType: .sessionHandoff,
            payload: "{\"agentType\":\"\(agentState.agentType.rawValue)\",\"decisionsCount\":\(mergedDecisions.count)}"
        )
        try await harnessEventRepo.save(event)

        logger.info("Session handoff generated for \(session.id) at \(projectRoot)")
    }

    func readExistingContext(projectRoot: String) -> HandoffContext? {
        let dirPath = (projectRoot as NSString).appendingPathComponent(
            AppConfig.SessionHandoff.directoryName
        )
        let filePath = (dirPath as NSString).appendingPathComponent(
            AppConfig.SessionHandoff.contextFileName
        )
        do {
            let content = try String(contentsOfFile: filePath, encoding: .utf8)
            return parseContextMarkdown(content)
        } catch {
            return nil
        }
    }

    // MARK: - File I/O

    private func writeContextFile(
        context: HandoffContext,
        projectRoot: String
    ) throws {
        let dirPath = (projectRoot as NSString).appendingPathComponent(
            AppConfig.SessionHandoff.directoryName
        )
        let filePath = (dirPath as NSString).appendingPathComponent(
            AppConfig.SessionHandoff.contextFileName
        )

        // Ensure directory exists
        if !fileManager.fileExists(atPath: dirPath) {
            try fileManager.createDirectory(
                atPath: dirPath,
                withIntermediateDirectories: true
            )
        }

        // Backup existing file before overwrite
        let backupPath = filePath + ".backup"
        var backedUp = false
        if fileManager.fileExists(atPath: filePath) {
            let existing = try String(contentsOfFile: filePath, encoding: .utf8)
            try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
            backedUp = true
        }

        let markdown = renderContextMarkdown(context)
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)

        // Clean up backup only after successful write
        if backedUp {
            do {
                try fileManager.removeItem(atPath: backupPath)
            } catch {
                logger.error("Failed to remove handoff backup: \(error)")
            }
        }
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
                let isError = lower.contains("error") || lower.contains("fatal")
                    || lower.contains("traceback") || lower.contains("panic")
                    || lower.contains("failed")
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

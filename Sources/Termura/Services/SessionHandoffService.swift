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
        let message = SessionMessage(
            sessionID: session.id,
            role: .system,
            contentType: .metadata,
            content: "[Session Handoff] Context written to \(projectRoot)/\(AppConfig.SessionHandoff.directoryName)/\(AppConfig.SessionHandoff.contextFileName)"
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
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return nil
        }
        return parseContextMarkdown(content)
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
        if fileManager.fileExists(atPath: filePath) {
            let existing = try String(contentsOfFile: filePath, encoding: .utf8)
            try existing.write(toFile: backupPath, atomically: true, encoding: .utf8)
        }
        defer { try? fileManager.removeItem(atPath: backupPath) }

        let markdown = renderContextMarkdown(context)
        try markdown.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Markdown Rendering

    private func renderContextMarkdown(_ context: HandoffContext) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = formatter.string(from: context.lastUpdated)

        let agentName = context.agentType.map { $0.rawValue } ?? "Unknown"
        let durationMin = Int(context.sessionDuration / 60)
        let durationStr = durationMin > 0 ? "\(durationMin)min" : "<1min"

        var lines: [String] = []
        lines.append("# Session Context (Auto-generated by Termura)")
        lines.append("")
        lines.append("> Last updated: \(dateStr) | Agent: \(agentName) | Duration: \(durationStr)")
        lines.append("")

        // Task Status
        lines.append("## Current Task Status")
        lines.append("")
        lines.append(context.taskStatus)
        lines.append("")

        // Decisions
        if !context.decisions.isEmpty {
            lines.append("## Recent Decisions")
            lines.append("")
            for entry in context.decisions {
                let ts = formatter.string(from: entry.timestamp)
                lines.append("- **\(ts)**: \(entry.summary)")
            }
            lines.append("")
        }

        // Errors
        if !context.errors.isEmpty {
            lines.append("## Key Errors Encountered")
            lines.append("")
            for error in context.errors {
                lines.append("- `\(error)`")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    private func parseContextMarkdown(_ content: String) -> HandoffContext? {
        let lines = content.components(separatedBy: "\n")
        var taskStatus = ""
        var decisions: [DecisionEntry] = []
        var currentSection = ""
        var agentType: AgentType?

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        for line in lines {
            // Parse agent type from header: "> Last updated: ... | Agent: claudeCode | ..."
            if line.hasPrefix("> Last updated:"), agentType == nil {
                agentType = parseAgentTypeFromHeader(line)
            }

            if line.hasPrefix("## Current Task Status") {
                currentSection = "task"
                continue
            } else if line.hasPrefix("## Recent Decisions") {
                currentSection = "decisions"
                continue
            } else if line.hasPrefix("## ") {
                currentSection = "other"
                continue
            }

            switch currentSection {
            case "task":
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if !taskStatus.isEmpty { taskStatus += "\n" }
                    taskStatus += trimmed
                }
            case "decisions":
                if let entry = parseDecisionLine(line, formatter: formatter) {
                    decisions.append(entry)
                }
            default:
                break
            }
        }

        guard !taskStatus.isEmpty || !decisions.isEmpty else { return nil }

        return HandoffContext(
            taskStatus: taskStatus,
            decisions: decisions,
            errors: [],
            agentType: agentType,
            sessionDuration: 0,
            lastUpdated: Date()
        )
    }

    /// Extracts agent type from a header line like "> Last updated: ... | Agent: claudeCode | ..."
    private func parseAgentTypeFromHeader(_ line: String) -> AgentType? {
        guard let agentRange = line.range(of: "Agent: ") else { return nil }
        let afterAgent = line[agentRange.upperBound...]
        let name: String
        if let pipeRange = afterAgent.range(of: " |") {
            name = String(afterAgent[..<pipeRange.lowerBound])
        } else {
            name = String(afterAgent).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return AgentType(rawValue: name)
    }

    private func parseDecisionLine(
        _ line: String,
        formatter: DateFormatter
    ) -> DecisionEntry? {
        // Format: - **2026-03-22 00:30**: Summary text
        guard line.hasPrefix("- **") else { return nil }
        let stripped = String(line.dropFirst(4)) // remove "- **"
        guard let endBold = stripped.range(of: "**:") else { return nil }
        let dateStr = String(stripped[stripped.startIndex..<endBold.lowerBound])
        let summaryStart = stripped.index(endBold.upperBound, offsetBy: 0)
        let summary = String(stripped[summaryStart...])
            .trimmingCharacters(in: .whitespaces)
        guard let date = formatter.date(from: dateStr) else { return nil }
        return DecisionEntry(timestamp: date, summary: summary)
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

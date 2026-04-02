import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ContextInjectionService")

/// Builds context injection text from a project's `.termura/context.md` for
/// auto-sending into a restored terminal session.
actor ContextInjectionService: ContextInjectionServiceProtocol {
    private let handoffService: any SessionHandoffServiceProtocol

    init(handoffService: any SessionHandoffServiceProtocol) {
        self.handoffService = handoffService
    }

    // MARK: - Public

    /// Returns formatted injection text for the given project root, or nil if no context exists.
    func buildInjectionText(projectRoot: String) async -> String? {
        guard let context = await handoffService.readExistingContext(projectRoot: projectRoot) else {
            return nil
        }

        let text: String = if let agentType = context.agentType, agentType != .unknown {
            formatForAgent(context, agentType: agentType)
        } else {
            formatForShell(context)
        }

        guard !text.isEmpty else { return nil }

        return String(text.prefix(AppConfig.SessionHandoff.injectionMaxLength))
    }

    // MARK: - Formatting per agent type

    /// Agents with a known resume command: send `resumeCommand` directly to PTY.
    /// Falls back to shell context injection for agents without a resume command
    /// or when the agent type is unknown.
    private func formatForAgent(_ context: HandoffContext, agentType: AgentType) -> String {
        let command = agentType.resumeCommand
        guard !command.isEmpty else { return "" }
        return command + "\n"
    }

    private func formatForShell(_ context: HandoffContext) -> String {
        let hasTask = !context.taskStatus.isEmpty
            && !context.taskStatus.lowercased().contains("empty")
        let recentDecisions = context.decisions.suffix(3)
        let hasDecisions = !recentDecisions.isEmpty

        // Nothing meaningful to inject.
        guard hasTask || hasDecisions else { return "" }

        var lines: [String] = []
        lines.append("--- Restored session context ---")

        if hasTask {
            lines.append("Task: \(context.taskStatus)")
        }

        if hasDecisions {
            lines.append("Decisions:")
            for entry in recentDecisions {
                lines.append("  - \(entry.summary)")
            }
        }

        lines.append("--- End context ---")

        let body = lines.joined(separator: "\n")
        let escaped = shellEscape(body)
        return "printf '%s\\n' \(escaped)\n"
    }

    // MARK: - Shell safety

    /// Wraps a string in single quotes with proper escaping for POSIX shells.
    /// Single quotes inside the value are handled by ending the quoted segment,
    /// inserting an escaped single quote, and reopening single quotes.
    private func shellEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}

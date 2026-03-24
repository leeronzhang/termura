import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ContextInjectionService")

/// Builds context injection text from a project's `.termura/context.md` for
/// auto-sending into a restored terminal session.
actor ContextInjectionService {

    private let handoffService: SessionHandoffService

    init(handoffService: SessionHandoffService) {
        self.handoffService = handoffService
    }

    // MARK: - Public

    /// Returns formatted injection text for the given project root, or nil if no context exists.
    func buildInjectionText(projectRoot: String) async -> String? {
        guard let context = await handoffService.readExistingContext(projectRoot: projectRoot) else {
            return nil
        }

        let text: String
        switch context.agentType {
        case .claudeCode:
            text = formatForClaudeCode(context)
        case .aider:
            text = formatForAider(context)
        default:
            text = formatForShell(context)
        }

        guard !text.isEmpty else { return nil }

        return String(text.prefix(AppConfig.SessionHandoff.injectionMaxLength))
    }

    // MARK: - Formatting per agent type

    /// Claude Code: launch `claude --continue` to resume the previous conversation.
    private func formatForClaudeCode(_ context: HandoffContext) -> String {
        "claude --continue\n"
    }

    /// Aider: launch `aider` to resume (aider auto-loads .aider.chat.history).
    private func formatForAider(_ context: HandoffContext) -> String {
        "aider\n"
    }

    private func formatForShell(_ context: HandoffContext) -> String {
        var lines: [String] = []
        lines.append("--- Restored session context ---")

        if !context.taskStatus.isEmpty {
            lines.append("Task: \(context.taskStatus)")
        }

        let recentDecisions = context.decisions.suffix(3)
        if !recentDecisions.isEmpty {
            lines.append("Decisions:")
            for entry in recentDecisions {
                lines.append("  - \(entry.summary)")
            }
        }

        lines.append("--- End context ---")

        let body = lines.joined(separator: "\\n")
        return "echo \"\(body)\"\n"
    }
}

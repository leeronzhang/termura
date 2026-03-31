import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "InterventionService")

/// Detects high-risk operations in agent output and triggers confirmation.
/// Stateless — all logic operates on static data; no actor isolation needed.
enum InterventionService {
    // MARK: - Detection

    /// Check if output text contains high-risk patterns.
    /// Only fires when `agentStatus == .toolRunning` — gates out false positives
    /// from commands discussed in agent prose vs. actually being executed.
    /// Returns the matched risk alert including the triggering command snippet, or nil if safe.
    static func detectRisk(in text: String, agentStatus: AgentStatus) -> RiskAlert? {
        guard agentStatus == .toolRunning else { return nil }
        // Fast-path: scan only the trailing window — risk commands appear near the end
        // of the agent's current output burst. Keeps `sample` as a Substring to avoid the
        // intermediate String copy when text exceeds the window; Substring.lowercased()
        // materializes directly to the final lowercased String in a single step.
        let maxLen = AppConfig.Agent.riskDetectionSuffixLength
        let sample = text.count > maxLen ? text.suffix(maxLen) : text[text.startIndex...]
        let lowered = sample.lowercased()
        // Fast-path: risk commands share a small set of literal anchor substrings.
        // Checking these O(1) anchors first avoids iterating all 10 riskPatterns on
        // the vast majority of output that contains none of them (CLAUDE.md §3.7).
        guard lowered.contains("rm -")
            || lowered.contains("git push")
            || lowered.contains("git reset")
            || lowered.contains("drop ")
            || lowered.contains("chmod")
            || lowered.contains("truncate")
            || lowered.contains("> /dev/")
            || lowered.contains("mkfs") else {
            return nil
        }
        for pattern in riskPatterns where lowered.contains(pattern.trigger) {
            let snippet = extractSnippet(from: sample, trigger: pattern.trigger)
            logger.warning("Risk detected: \(pattern.description) — \(snippet)")
            return RiskAlert(
                trigger: pattern.trigger,
                description: pattern.description,
                severity: pattern.severity,
                commandSnippet: snippet
            )
        }
        return nil
    }

    // MARK: - Snippet extraction

    /// Returns the first line of `sample` that contains `trigger` (case-insensitive),
    /// trimmed and truncated to `AppConfig.Agent.riskSnippetMaxLength` chars.
    /// Falls back to the trigger keyword itself if no matching line can be isolated.
    private static func extractSnippet(from sample: Substring, trigger: String) -> String {
        let lines = sample.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines where line.lowercased().contains(trigger) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return String(trimmed.prefix(AppConfig.Agent.riskSnippetMaxLength))
        }
        return trigger
    }

    // MARK: - Risk Patterns

    private struct RiskPattern: Sendable {
        let trigger: String
        let description: String
        let severity: RiskSeverity
    }

    private static let riskPatterns: [RiskPattern] = [
        RiskPattern(trigger: "rm -rf", description: "Recursive force delete", severity: .critical),
        RiskPattern(trigger: "git push --force", description: "Force push to remote", severity: .critical),
        RiskPattern(trigger: "git push -f", description: "Force push to remote", severity: .critical),
        RiskPattern(trigger: "drop table", description: "Database table deletion", severity: .critical),
        RiskPattern(trigger: "drop database", description: "Database deletion", severity: .critical),
        RiskPattern(trigger: "git reset --hard", description: "Hard reset (discards changes)", severity: .high),
        RiskPattern(trigger: "chmod 777", description: "Open permissions to all", severity: .high),
        RiskPattern(trigger: "truncate", description: "Data truncation", severity: .high),
        RiskPattern(trigger: "> /dev/", description: "Device write redirect", severity: .critical),
        RiskPattern(trigger: "mkfs", description: "Filesystem format", severity: .critical)
    ]
}

// MARK: - Risk Alert Model

struct RiskAlert: Sendable, Identifiable {
    let id = UUID()
    let trigger: String
    let description: String
    let severity: RiskSeverity
    /// The specific line from the terminal output that matched the risk pattern.
    /// Shown in the alert banner so the user can see the exact command.
    let commandSnippet: String
}

enum RiskSeverity: String, Sendable {
    case high
    case critical
}

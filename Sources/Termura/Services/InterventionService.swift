import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "InterventionService")

/// Detects high-risk operations in agent output and triggers confirmation.
actor InterventionService {

    // MARK: - Detection

    /// Check if output text contains high-risk patterns.
    /// Returns the matched risk description, or nil if safe.
    func detectRisk(in text: String) -> RiskAlert? {
        let lowered = text.lowercased()
        for pattern in Self.riskPatterns {
            if lowered.contains(pattern.trigger) {
                logger.warning("Risk detected: \(pattern.description)")
                return pattern
            }
        }
        return nil
    }

    // MARK: - Risk Patterns

    private static let riskPatterns: [RiskAlert] = [
        RiskAlert(trigger: "rm -rf", description: "Recursive force delete", severity: .critical),
        RiskAlert(trigger: "git push --force", description: "Force push to remote", severity: .critical),
        RiskAlert(trigger: "git push -f", description: "Force push to remote", severity: .critical),
        RiskAlert(trigger: "drop table", description: "Database table deletion", severity: .critical),
        RiskAlert(trigger: "drop database", description: "Database deletion", severity: .critical),
        RiskAlert(trigger: "git reset --hard", description: "Hard reset (discards changes)", severity: .high),
        RiskAlert(trigger: "chmod 777", description: "Open permissions to all", severity: .high),
        RiskAlert(trigger: "truncate", description: "Data truncation", severity: .high),
        RiskAlert(trigger: "> /dev/", description: "Device write redirect", severity: .critical),
        RiskAlert(trigger: "mkfs", description: "Filesystem format", severity: .critical)
    ]
}

// MARK: - Risk Alert Model

struct RiskAlert: Sendable, Identifiable {
    let id = UUID()
    let trigger: String
    let description: String
    let severity: RiskSeverity
}

enum RiskSeverity: String, Sendable {
    case high
    case critical
}

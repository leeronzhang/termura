import Foundation

/// Result of a corruption scan on a rule file section.
struct CorruptionResult: Identifiable, Sendable {
    let id = UUID()
    let severity: CorruptionSeverity
    let category: CorruptionCategory
    let message: String
    let sectionHeading: String
    let lineRange: ClosedRange<Int>
}

/// Severity level for corruption findings.
enum CorruptionSeverity: String, Sendable {
    case info
    case warning
    case error
}

/// Category of corruption issue.
enum CorruptionCategory: String, Sendable {
    /// File path referenced in rule no longer exists.
    case stalePath
    /// Contradictory instructions within or across sections.
    case contradiction
    /// Duplicate or near-duplicate sections.
    case redundancy
}

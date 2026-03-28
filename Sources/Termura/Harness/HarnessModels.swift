import Foundation

// MARK: - RuleFileRecord

struct RuleFileRecord: Identifiable, Sendable {
    let id: UUID
    let filePath: String
    let content: String
    let contentHash: String
    let sessionID: SessionID?
    let version: Int
    let createdAt: Date

    var fileName: String { URL(fileURLWithPath: filePath).lastPathComponent }
}

// MARK: - RuleSection

struct RuleSection: Identifiable, Sendable {
    let id: UUID
    let heading: String
    let level: Int
    let body: String
    let lineRange: ClosedRange<Int>
}

// MARK: - CorruptionSeverity / Category

enum CorruptionSeverity: String, Sendable {
    case info, warning, error
}

enum CorruptionCategory: String, Sendable {
    case stalePath
    case contradiction
    case redundancy
}

// MARK: - CorruptionResult

struct CorruptionResult: Identifiable, Sendable {
    let id = UUID()
    let severity: CorruptionSeverity
    let category: CorruptionCategory
    let message: String
    let sectionHeading: String
    let lineRange: ClosedRange<Int>
}

// MARK: - RuleDraft / ErrorSummary

struct RuleDraft: Sendable {
    let errorChunkID: UUID
    let sessionID: SessionID
    let suggestedRule: String
    let errorSummary: ErrorSummary
}

struct ErrorSummary: Sendable {
    let title: String
    let context: String
    let antiPattern: String
    let suggestion: String
}

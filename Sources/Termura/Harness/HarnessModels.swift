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

    init(
        id: UUID = UUID(),
        filePath: String,
        content: String,
        contentHash: String = "",
        sessionID: SessionID? = nil,
        version: Int = 1,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.filePath = filePath
        self.content = content
        self.contentHash = contentHash.isEmpty ? Self.hash(content) : contentHash
        self.sessionID = sessionID
        self.version = version
        self.createdAt = createdAt
    }

    // FNV-1a hash — no CryptoKit dependency required.
    private static func hash(_ string: String) -> String {
        var fnv: UInt64 = 14_695_981_039_346_656_037
        for byte in Data(string.utf8) {
            fnv ^= UInt64(byte)
            fnv &*= 1_099_511_628_211
        }
        return String(format: "%016llx", fnv)
    }
}

// MARK: - RuleSection

struct RuleSection: Identifiable, Sendable {
    let id: UUID
    let heading: String
    let level: Int
    let body: String
    let lineRange: ClosedRange<Int>

    init(id: UUID = UUID(), heading: String, level: Int, body: String, lineRange: ClosedRange<Int>) {
        self.id = id
        self.heading = heading
        self.level = level
        self.body = body
        self.lineRange = lineRange
    }
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

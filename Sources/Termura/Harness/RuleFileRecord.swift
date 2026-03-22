import Foundation

/// Represents a snapshot of a harness rule file (AGENTS.md, CLAUDE.md, etc.).
struct RuleFileRecord: Identifiable, Sendable {
    let id: UUID
    /// Absolute path to the rule file on disk.
    let filePath: String
    /// Full content at this version.
    let content: String
    /// SHA-256 hash of content for change detection.
    let contentHash: String
    /// Associated session ID if the snapshot was triggered during a session.
    let sessionID: SessionID?
    /// Incrementing version number for this file path.
    let version: Int
    let createdAt: Date

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

    /// File name without directory path.
    var fileName: String {
        URL(fileURLWithPath: filePath).lastPathComponent
    }

    private static func hash(_ string: String) -> String {
        let data = Data(string.utf8)
        // FNV-1a hash as hex string (no CryptoKit dependency)
        var h: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            h ^= UInt64(byte)
            h &*= 1_099_511_628_211
        }
        return String(format: "%016llx", h)
    }
}

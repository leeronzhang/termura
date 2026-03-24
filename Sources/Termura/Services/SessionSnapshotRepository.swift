import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionSnapshotRepository")

actor SessionSnapshotRepository {
    private let db: any DatabaseServiceProtocol

    init(db: any DatabaseServiceProtocol) { self.db = db }

    func save(lines: [String], for sessionID: SessionID) async throws {
        let capped = Array(lines.suffix(AppConfig.Persistence.snapshotMaxLines))
        let compressed = try compress(capped)
        let idStr = sessionID.rawValue.uuidString
        let now = Date().timeIntervalSince1970
        let count = capped.count
        try await db.write { database in
            try database.execute(
                sql: """
                INSERT OR REPLACE INTO session_snapshots
                    (session_id, compressed_data, line_count, saved_at)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [idStr, compressed, count, now]
            )
        }
        logger.info("Snapshot saved for session \(idStr): \(count) lines")
    }

    func load(for sessionID: SessionID) async throws -> [String]? {
        let idStr = sessionID.rawValue.uuidString
        let result = try await db.read { database -> (Data, Int)? in
            guard let row = try Row.fetchOne(
                database,
                sql: """
                SELECT compressed_data, line_count
                FROM session_snapshots WHERE session_id = ?
                """,
                arguments: [idStr]
            ) else { return nil }
            let data: Data = row["compressed_data"]
            let lineCount: Int = row["line_count"]
            return (data, lineCount)
        }
        guard let (data, _) = result else { return nil }
        return try decompress(data)
    }

    func delete(for sessionID: SessionID) async throws {
        let idStr = sessionID.rawValue.uuidString
        try await db.write { database in
            try database.execute(
                sql: "DELETE FROM session_snapshots WHERE session_id = ?",
                arguments: [idStr]
            )
        }
    }

    // MARK: - LZFSE helpers

    private func compress(_ lines: [String]) throws -> Data {
        let text = lines.joined(separator: "\n")
        guard let data = text.data(using: .utf8) else {
            throw RepositoryError.compressionFailed
        }
        do {
            return try (data as NSData).compressed(using: .lzfse) as Data
        } catch {
            throw RepositoryError.compressionFailed
        }
    }

    private func decompress(_ data: Data) throws -> [String] {
        do {
            let plain = try (data as NSData).decompressed(using: .lzfse) as Data
            guard let text = String(data: plain, encoding: .utf8) else {
                throw RepositoryError.compressionFailed
            }
            return text.components(separatedBy: "\n")
        } catch {
            throw RepositoryError.compressionFailed
        }
    }
}

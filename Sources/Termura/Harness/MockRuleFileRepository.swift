import Foundation

/// Test double for `RuleFileRepositoryProtocol`.
actor MockRuleFileRepository: RuleFileRepositoryProtocol {
    var savedRecords: [RuleFileRecord] = []

    func save(_ record: RuleFileRecord) async throws {
        savedRecords.append(record)
    }

    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] {
        savedRecords.filter { $0.filePath == filePath }
            .sorted { $0.version > $1.version }
    }

    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? {
        savedRecords.filter { $0.filePath == filePath }
            .max(by: { $0.version < $1.version })
    }

    func fetchAll() async throws -> [RuleFileRecord] {
        var latest: [String: RuleFileRecord] = [:]
        for record in savedRecords {
            let current = latest[record.filePath]?.version ?? 0
            if record.version > current {
                latest[record.filePath] = record
            }
        }
        return Array(latest.values)
    }
}

import Foundation

// MARK: - Protocol

protocol RuleFileRepositoryProtocol: Actor {
    func save(_ record: RuleFileRecord) async throws
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord]
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord?
    func fetchAll() async throws -> [RuleFileRecord]
}

// MARK: - Null Object (production stub for Free builds without HARNESS_ENABLED)

actor NullRuleFileRepository: RuleFileRepositoryProtocol {
    func save(_ record: RuleFileRecord) async throws {}
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] { [] }
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? { nil }
    func fetchAll() async throws -> [RuleFileRecord] { [] }
}

// MARK: - Mock (debug/test only)

#if DEBUG

actor MockRuleFileRepository: RuleFileRepositoryProtocol {
    private var records: [RuleFileRecord] = []

    /// All records that have been saved -- accessible from tests for verification.
    var savedRecords: [RuleFileRecord] { records }

    func save(_ record: RuleFileRecord) async throws {
        records.removeAll { $0.filePath == record.filePath && $0.id == record.id }
        records.append(record)
    }

    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] {
        records.filter { $0.filePath == filePath }
    }

    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? {
        records.last { $0.filePath == filePath }
    }

    func fetchAll() async throws -> [RuleFileRecord] {
        records
    }
}

#endif

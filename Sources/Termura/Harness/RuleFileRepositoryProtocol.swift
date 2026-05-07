import Foundation

// MARK: - Protocol

protocol RuleFileRepositoryProtocol: Actor {
    func save(_ record: RuleFileRecord) async throws
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord]
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord?
    func fetchAll() async throws -> [RuleFileRecord]
}

// MARK: - Null Object (preview / test fallback when no DB-backed repository is needed)

actor NullRuleFileRepository: RuleFileRepositoryProtocol {
    func save(_ record: RuleFileRecord) async throws {}
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] { [] }
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? { nil }
    func fetchAll() async throws -> [RuleFileRecord] { [] }
}

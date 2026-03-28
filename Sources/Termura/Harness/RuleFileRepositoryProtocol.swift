import Foundation

// MARK: - Protocol

protocol RuleFileRepositoryProtocol: Actor {
    func save(_ record: RuleFileRecord) async throws
    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord]
    func fetchLatest(for filePath: String) async throws -> RuleFileRecord?
    func fetchAll() async throws -> [RuleFileRecord]
}

// MARK: - Mock (used as default in free build and SwiftUI previews)

actor MockRuleFileRepository: RuleFileRepositoryProtocol {
    private var records: [RuleFileRecord] = []

    func save(_ record: RuleFileRecord) async throws {
        records.removeAll { $0.filePath == record.filePath && $0.id == record.id }
        records.append(record)
    }

    func fetchHistory(for filePath: String) async throws -> [RuleFileRecord] {
        records.filter { $0.filePath == filePath }
    }

    func fetchLatest(for filePath: String) async throws -> RuleFileRecord? {
        records.filter { $0.filePath == filePath }.last
    }

    func fetchAll() async throws -> [RuleFileRecord] {
        records
    }
}

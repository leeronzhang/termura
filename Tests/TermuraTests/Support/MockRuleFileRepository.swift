import Foundation
@testable import Termura

actor MockRuleFileRepository: RuleFileRepositoryProtocol {
    private var records: [RuleFileRecord] = []

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

import Foundation
import GRDB
@testable import Termura

actor MockDatabaseService: DatabaseServiceProtocol {
    private let queue: DatabaseQueue

    init() throws {
        queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(queue)
    }

    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await queue.read(block)
    }

    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await queue.write(block)
    }
}

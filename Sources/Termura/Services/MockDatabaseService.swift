import Foundation
import GRDB

#if DEBUG

/// In-memory database service for unit tests. Applies all real migrations.
actor MockDatabaseService: DatabaseServiceProtocol {
    private let queue: DatabaseQueue

    init() throws {
        queue = try DatabaseQueue() // in-memory
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

#endif

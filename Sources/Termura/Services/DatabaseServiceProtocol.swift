import Foundation
import GRDB

/// Protocol for database access — all conformers are actors for strict isolation.
/// Live implementation: DatabaseService (DatabasePool).
/// Test implementation: MockDatabaseService (in-memory DatabaseQueue).
protocol DatabaseServiceProtocol: Actor {
    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T
    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T
}

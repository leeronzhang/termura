import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "DatabaseService")

actor DatabaseService: DatabaseServiceProtocol {
    private let pool: DatabasePool

    /// Designated init — inject a pre-configured pool (enables testing with in-memory pools).
    init(pool: DatabasePool) throws {
        self.pool = pool
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(pool)
        logger.info("DatabaseService ready — migrations applied")
    }

    /// Convenience factory — creates the pool at the standard ~/.termura/ path.
    static func makePool() throws -> DatabasePool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(AppConfig.Persistence.directoryName)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(AppConfig.Persistence.databaseFileName)
        var config = Configuration()
        config.label = "com.termura.db"
        return try DatabasePool(path: url.path, configuration: config)
    }

    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await pool.read(block)
    }

    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        try await pool.write(block)
    }
}

import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "DatabaseService")

actor DatabaseService: DatabaseServiceProtocol {
    private let pool: DatabasePool
    private let metrics: (any MetricsCollectorProtocol)?

    /// Designated init — inject a pre-configured pool (enables testing with in-memory pools).
    /// Runs DB migrations on the actor's executor (background thread) to avoid blocking the main thread.
    init(pool: DatabasePool, metrics: (any MetricsCollectorProtocol)? = nil /* Optional: observability, nil = no-op */) async throws {
        self.pool = pool
        self.metrics = metrics
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(pool)
        logger.info("DatabaseService ready — migrations applied")
    }

    /// Creates a pool at `<projectURL>/.termura/termura.db`.
    /// Non-isolated async so the filesystem and SQLite calls run on the cooperative
    /// thread pool, not on the MainActor — even when called from a @MainActor context.
    /// - Throws: `RepositoryError.databaseNotAccessible` if the directory is not writable.
    static func makePool(at projectURL: URL) async throws -> DatabasePool {
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: projectURL.path) else {
            throw RepositoryError.databaseNotAccessible(path: projectURL.path)
        }
        let dir = projectURL.appendingPathComponent(AppConfig.Persistence.directoryName)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(AppConfig.Persistence.databaseFileName)
        var config = Configuration()
        config.label = "com.termura.db.\(projectURL.lastPathComponent)"
        return try DatabasePool(path: url.path, configuration: config)
    }

    func read<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        await metrics?.increment(.dbRead)
        let start = ContinuousClock.now
        let result = try await pool.read(block)
        let elapsed = ContinuousClock.now - start
        await metrics?.recordDuration(.dbReadDuration, seconds: elapsed.totalSeconds)
        return result
    }

    func write<T: Sendable>(_ block: @Sendable (Database) throws -> T) async throws -> T {
        await metrics?.increment(.dbWrite)
        let start = ContinuousClock.now
        let result = try await pool.write(block)
        let elapsed = ContinuousClock.now - start
        await metrics?.recordDuration(.dbWriteDuration, seconds: elapsed.totalSeconds)
        return result
    }
}

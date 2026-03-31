import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectMigration")

/// One-time migration that splits the global `~/.termura/termura.db` into
/// per-project databases at `<project>/.termura/termura.db`.
enum ProjectMigrationService {
    static var needsMigration: Bool { checkNeedsMigration(using: UserDefaults.standard) }

    static func checkNeedsMigration(using userDefaults: any UserDefaultsStoring) -> Bool {
        guard !userDefaults.bool(forKey: AppConfig.UserDefaultsKeys.projectMigrationCompleted) else { return false }
        let home = URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
        let legacyDB = home
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Persistence.databaseFileName)
        return FileManager.default.fileExists(atPath: legacyDB.path)
    }

    /// Reads all sessions from the legacy DB, groups by `workingDirectory`,
    /// and copies each group's data into a per-project database.
    static func migrateIfNeeded(
        using userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) async {
        guard checkNeedsMigration(using: userDefaults) else { return }
        let home = URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
        let legacyDir = home.appendingPathComponent(AppConfig.Persistence.directoryName)
        let legacyPath = legacyDir.appendingPathComponent(AppConfig.Persistence.databaseFileName)

        do {
            let legacyPool = try DatabasePool(path: legacyPath.path)
            let projects = try await legacyPool.read { db -> [String] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT working_directory FROM sessions
                    WHERE working_directory IS NOT NULL AND working_directory != ''
                """)
                return rows.map { $0["working_directory"] as String }
            }

            for projectPath in projects {
                try await migrateProject(projectPath: projectPath, legacyPool: legacyPool)
            }

            // Rename legacy DB as backup
            let backupPath = legacyDir.appendingPathComponent("termura.db.migrated")
            try FileManager.default.moveItem(at: legacyPath, to: backupPath)

            userDefaults.set(true, forKey: AppConfig.UserDefaultsKeys.projectMigrationCompleted)
            logger.info("Migration complete — \(projects.count) projects migrated")
        } catch {
            logger.error("Project migration failed: \(error)")
        }
    }

    // MARK: - Private

    private static func migrateProject(projectPath: String, legacyPool: DatabasePool) async throws {
        let projectURL = URL(fileURLWithPath: projectPath)
        guard FileManager.default.fileExists(atPath: projectPath) else {
            logger.warning("Skipping missing project directory: \(projectPath)")
            return
        }

        let newPool = try await DatabaseService.makePool(at: projectURL)
        // Apply migrations to the new pool
        var migrator = DatabaseMigrator()
        DatabaseMigrations.register(into: &migrator)
        try migrator.migrate(newPool)

        // Get session IDs for this project
        let sessionIDs: [String] = try await legacyPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id FROM sessions WHERE working_directory = ?
            """, arguments: [projectPath])
            return rows.map { $0["id"] as String }
        }
        guard !sessionIDs.isEmpty else { return }

        try await copySessionData(
            sessionIDs: sessionIDs,
            projectPath: projectPath,
            legacyPool: legacyPool,
            targetPool: newPool
        )

        logger.info("Migrated \(sessionIDs.count) sessions to \(projectPath)")
    }

    private static func copySessionData(
        sessionIDs: [String],
        projectPath: String,
        legacyPool: DatabasePool,
        targetPool: DatabasePool
    ) async throws {
        let batchSize = AppConfig.Persistence.inClauseBatchSize
        try await targetPool.write { target in
            try copyTable("sessions", where: "working_directory = ?", args: [projectPath], from: legacyPool, into: target)
            // Batch IN clauses to stay below SQLite's SQLITE_LIMIT_VARIABLE_NUMBER (999).
            for table in ["session_messages", "harness_events", "session_snapshots"] {
                for batchStart in stride(from: 0, to: sessionIDs.count, by: batchSize) {
                    let batch = Array(sessionIDs[batchStart ..< min(batchStart + batchSize, sessionIDs.count)])
                    let placeholders = batch.map { _ in "?" }.joined(separator: ",")
                    let idArgs = batch.map { $0 as any DatabaseValueConvertible }
                    try copyTable(table, where: "session_id IN (\(placeholders))", args: idArgs, from: legacyPool, into: target)
                }
            }
            try copyTable("notes", where: "1=1", args: [], from: legacyPool, into: target)
        }
    }

    // Exhaustive whitelist of tables this migration is permitted to touch.
    // Any caller passing a name outside this set is a programmer error — crash in
    // Debug and Release alike so the mistake surfaces immediately during development.
    private static let allowedMigrationTables: Set<String> = [
        "sessions", "session_messages", "harness_events", "session_snapshots", "notes"
    ]

    /// Copies rows from a table in the legacy DB to the target database.
    ///
    /// - Note: Dynamic SQL safety contract:
    ///   - `table` is validated against `allowedMigrationTables` above; not user input.
    ///   - `clause` is hardcoded at every call site ("working_directory = ?",
    ///     "session_id IN (?,...)", "1=1") or built solely from "?" placeholders.
    ///   - `columnList` comes from `row.columnNames` (DB schema), not user input.
    ///   - All actual runtime values are passed via `StatementArguments` (parameterized).
    private static func copyTable(
        _ table: String,
        where clause: String,
        args: [any DatabaseValueConvertible],
        from legacy: DatabasePool,
        into target: Database
    ) throws {
        precondition(allowedMigrationTables.contains(table), "copyTable called with unexpected table '\(table)'")
        let rows = try legacy.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM \(table) WHERE \(clause)",
                             arguments: StatementArguments(args))
        }
        for row in rows {
            let columns = row.columnNames
            let columnList = columns.joined(separator: ", ")
            let placeholderList = columns.map { _ in "?" }.joined(separator: ", ")
            let values = columns.map { row[$0] as DatabaseValue }
            try target.execute(
                sql: "INSERT OR IGNORE INTO \(table) (\(columnList)) VALUES (\(placeholderList))",
                arguments: StatementArguments(values)
            )
        }
    }
}

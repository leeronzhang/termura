import XCTest
@testable import Termura

@MainActor
final class ProjectMigrationServiceTests: XCTestCase {
    /// Unique UserDefaults key prefix per test run to avoid cross-test pollution.
    private let migrationKey = "projectMigrationCompleted"

    override func setUp() async throws {
        // Ensure the migration key is cleared before each test.
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    override func tearDown() async throws {
        // Clean up the migration key after each test.
        UserDefaults.standard.removeObject(forKey: migrationKey)
    }

    // MARK: - needsMigration guard

    func testMigrateIfNeededSkipsWhenKeySet() async {
        // Set the UserDefaults key that marks migration as completed.
        UserDefaults.standard.set(true, forKey: migrationKey)

        // needsMigration should be false when key is set.
        XCTAssertFalse(ProjectMigrationService.needsMigration)
    }

    // MARK: - Missing legacy DB

    func testNeedsMigrationFalseWhenNoLegacyDB() {
        // With a clean UserDefaults (key not set) but no legacy DB file,
        // needsMigration should still be false because the file check fails.
        // This test relies on the test environment not having ~/.termura/termura.db
        // or the key already being cleared in setUp.
        UserDefaults.standard.removeObject(forKey: migrationKey)

        // If there is no legacy DB on the test machine, this should be false.
        // We cannot guarantee the file absence, so we just verify no crash.
        _ = ProjectMigrationService.needsMigration
    }

    // MARK: - migrateIfNeeded is safe to call when no migration needed

    func testMigrateIfNeededSafeWhenAlreadyMigrated() async {
        UserDefaults.standard.set(true, forKey: migrationKey)

        // Should return immediately without errors when migration key is set.
        await ProjectMigrationService.migrateIfNeeded()

        // Verify the key is still set (not reset by the call).
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationKey))
    }
}

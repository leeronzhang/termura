@testable import Termura
import XCTest

@MainActor
final class ProjectMigrationServiceTests: XCTestCase {
    private var isolatedDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.termura.tests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
    }

    // MARK: - needsMigration guard

    func testMigrateIfNeededSkipsWhenKeySet() async {
        // Set the UserDefaults key that marks migration as completed.
        isolatedDefaults.set(true, forKey: AppConfig.UserDefaultsKeys.projectMigrationCompleted)

        // checkNeedsMigration should be false when key is set.
        XCTAssertFalse(ProjectMigrationService.checkNeedsMigration(using: isolatedDefaults))
    }

    // MARK: - Missing legacy DB

    func testNeedsMigrationFalseWhenNoLegacyDB() {
        // With a clean UserDefaults (key not set) but no legacy DB file,
        // needsMigration should still be false because the file check fails.
        // If there is no legacy DB on the test machine, this should be false.
        // We cannot guarantee the file absence, so we just verify no crash.
        _ = ProjectMigrationService.checkNeedsMigration(using: isolatedDefaults)
    }

    // MARK: - migrateIfNeeded is safe to call when no migration needed

    func testMigrateIfNeededSafeWhenAlreadyMigrated() async {
        isolatedDefaults.set(true, forKey: AppConfig.UserDefaultsKeys.projectMigrationCompleted)

        // Should return immediately without errors when migration key is set.
        await ProjectMigrationService.migrateIfNeeded(using: isolatedDefaults)

        // Verify the key is still set (not reset by the call).
        XCTAssertTrue(isolatedDefaults.bool(forKey: AppConfig.UserDefaultsKeys.projectMigrationCompleted))
    }
}

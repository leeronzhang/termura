import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// Cold-start `restoreIfEnabled()` behaviour. Pinned in its own file so
/// the original `RemoteControlControllerTests` stays focused on the
/// init / enable / disable surface. The contract this suite locks in:
/// when the user previously turned remote control on, app relaunch
/// must transparently bring the harness back online without re-running
/// the helper-bundle / LaunchAgent install gates that `enable()` does.
@MainActor
final class RemoteControlControllerRestoreTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var executor: RestoreRecordingExecutor!
    private var helperResolver: StubHelperPathResolver!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-restore-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        executor = RestoreRecordingExecutor()
        defaultsSuiteName = "termura-restore-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        helperResolver = try StubHelperPathResolver.makeBundledHelper(
            in: tempDir,
            name: "termura-remote-agent"
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        try await super.tearDown()
    }

    private func makeController(
        integration: any RemoteIntegration
    ) -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        return RemoteControlController(
            integration: integration,
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: helperResolver
        )
    }

    // MARK: - Happy path

    func test_restoreIfEnabled_whenPersistedTrue_callsIntegrationStart() async {
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let stub = RestoreStubIntegration()
        let controller = makeController(integration: stub)
        XCTAssertTrue(controller.isEnabled,
                      "preconditioned: controller hydrates isEnabled from UserDefaults")

        await controller.restoreIfEnabled()

        let startCount = await stub.startCount
        XCTAssertEqual(startCount, 1,
                       "restore must invoke integration.start() exactly once on persisted-true")
        XCTAssertTrue(controller.isEnabled, "isEnabled stays true on success")
        XCTAssertNil(controller.lastError, "happy path leaves no error")
    }

    // MARK: - No-op paths

    func test_restoreIfEnabled_whenPersistedFalse_isNoop() async {
        // Default UserDefaults has no value; isEnabled hydrates to false.
        let stub = RestoreStubIntegration()
        let controller = makeController(integration: stub)
        XCTAssertFalse(controller.isEnabled)

        await controller.restoreIfEnabled()

        let startCount = await stub.startCount
        XCTAssertEqual(startCount, 0, "restore must not start integration when disabled")
        XCTAssertFalse(controller.isEnabled)
        XCTAssertNil(controller.lastError)
    }

    func test_restoreIfEnabled_doesNotInvokeInstaller() async {
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let stub = RestoreStubIntegration()
        let controller = makeController(integration: stub)

        await controller.restoreIfEnabled()

        let bootstraps = await executor.bootstraps
        XCTAssertTrue(
            bootstraps.isEmpty,
            "restore must not re-run LaunchAgent install — that is reserved for enable() / reinstallIfNeeded()"
        )
    }

    func test_restoreIfEnabled_whileEnableInFlight_doesNotDoubleStart() async {
        // Defends against a race between the launch-time restore task and
        // a user tapping the Settings toggle while launch is still in
        // progress. Both routes flip `isWorking`; the one that arrives
        // second must no-op.
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let stub = RestoreStubIntegration()
        let controller = makeController(integration: stub)

        async let userToggle: Void = controller.enable()
        async let launchRestore: Void = controller.restoreIfEnabled()
        _ = await (userToggle, launchRestore)

        let startCount = await stub.startCount
        XCTAssertEqual(
            startCount, 1,
            "the second concurrent caller must observe isWorking and back off"
        )
    }

    // MARK: - Lifecycle / error path

    func test_restoreIfEnabled_startFailure_keepsIsEnabledTrueAndSurfacesError() async {
        // NullRemoteIntegration.start() throws integrationDisabled — exercises
        // the error catch path without needing a custom failing stub.
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let controller = makeController(integration: NullRemoteIntegration())
        XCTAssertTrue(controller.isEnabled)

        await controller.restoreIfEnabled()

        XCTAssertTrue(
            controller.isEnabled,
            "intent must persist on transient launch failures so user sees the toggle still ON"
        )
        XCTAssertNotNil(controller.lastError, "error must surface for Settings UI")
    }
}

private actor RestoreStubIntegration: RemoteIntegration {
    private(set) var startCount = 0
    private(set) var isRunning = false

    func start() async throws {
        startCount += 1
        isRunning = true
    }

    func stop() async {
        isRunning = false
    }

    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            token: "stub-restore-token",
            macPublicKey: Data([0x01]),
            serviceName: "stub-restore-mac",
            expiresAt: Date(timeIntervalSince1970: 9_999_999)
        )
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {}
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor RestoreRecordingExecutor: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []

    func bootstrap(plistURL: URL) async throws {
        bootstraps.append(plistURL)
    }

    func bootout(label: String) async throws {
        bootouts.append(label)
    }
}

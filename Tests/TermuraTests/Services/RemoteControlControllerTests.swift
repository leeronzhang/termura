import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

@MainActor
final class RemoteControlControllerTests: XCTestCase {
    private var tempDir: URL!
    private var executor: RecordingLaunchControl!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-controller-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        executor = RecordingLaunchControl()
        defaultsSuiteName = "termura-controller-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
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
        integration: any RemoteIntegration,
        bridge: any RemoteAgentBridgeLifecycle = NullRemoteAgentBridgeLifecycle()
    ) -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        return RemoteControlController(
            integration: integration,
            agentBridge: bridge,
            userDefaults: defaults,
            installer: installer
        )
    }

    func testInitialStateIsDisabled() {
        let controller = makeController(integration: NullRemoteIntegration())
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(controller.isWorking)
        XCTAssertNil(controller.latestInvitationJSON)
        XCTAssertNil(controller.lastError)
    }

    func testEnableSurfacesIntegrationDisabledFromNull() async {
        let controller = makeController(integration: NullRemoteIntegration())
        await controller.enable()
        XCTAssertFalse(controller.isEnabled, "Null integration must not flip enabled flag")
        XCTAssertNotNil(controller.lastError)
        let bootstraps = await executor.bootstraps
        XCTAssertTrue(bootstraps.isEmpty,
                      "plist install must not run when integration startup failed")
    }

    func testDisableIsIdempotent() async {
        let controller = makeController(integration: NullRemoteIntegration())
        await controller.disable()
        await controller.disable()
        XCTAssertFalse(controller.isEnabled)
    }

    func testGenerateInvitationGuardedByEnabledState() async {
        let controller = makeController(integration: NullRemoteIntegration())
        await controller.generateInvitation()
        XCTAssertNil(controller.latestInvitationJSON,
                     "Invitation issuance must require an enabled integration")
    }

    func testEnableInstallsPlistAfterIntegrationStart() async {
        let stub = StubRemoteIntegration()
        let controller = makeController(integration: stub)
        await controller.enable()
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastError)

        let plistURL = tempDir.appendingPathComponent("com.termura.remote-agent.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let bootstraps = await executor.bootstraps
        XCTAssertEqual(bootstraps, [plistURL])
    }

    func testDisableRemovesPlist() async {
        let stub = StubRemoteIntegration()
        let controller = makeController(integration: stub)
        await controller.enable()
        await controller.disable()
        XCTAssertFalse(controller.isEnabled)

        let plistURL = tempDir.appendingPathComponent("com.termura.remote-agent.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
        let bootouts = await executor.bootouts
        XCTAssertTrue(bootouts.contains("com.termura.remote-agent"))
    }

    func testEnableSucceedsWithStubIntegration() async {
        let stub = StubRemoteIntegration()
        let controller = makeController(integration: stub)
        await controller.enable()
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastError)
        await controller.generateInvitation()
        XCTAssertNotNil(controller.latestInvitationJSON,
                        "Invitation should be rendered as JSON when integration provides one")
    }

    func testPlistInstallFailureRollsBackIntegration() async {
        let stub = StubRemoteIntegration()
        let failingExecutor = FailingLaunchControl()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: failingExecutor)
        let controller = RemoteControlController(
            integration: stub,
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer
        )

        await controller.enable()
        XCTAssertFalse(controller.isEnabled,
                       "plist install failure must roll back the integration")
        XCTAssertNotNil(controller.lastError)
        let stopped = await stub.stopCount
        XCTAssertEqual(stopped, 1, "rollback must stop the integration")
    }

    // MARK: - PR9 Step 0: dependency-surface migration

    func test_controllerInit_readsRemoteControlEnabledFromUserDefaults_true() {
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let controller = makeController(integration: NullRemoteIntegration())
        XCTAssertTrue(controller.isEnabled,
                      "init must surface the persisted enabled flag so a relaunch reflects the user's last choice")
    }

    func test_controllerInit_readsRemoteControlEnabledFromUserDefaults_false() {
        defaults.set(false, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let controller = makeController(integration: NullRemoteIntegration())
        XCTAssertFalse(controller.isEnabled)
    }

    func test_controllerInit_doesNotEagerlyStartIntegration() async {
        let stub = StubRemoteIntegration()
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        _ = makeController(integration: stub)
        // Even with the persisted flag set to true, init must not call
        // `start()` on the integration — actual transport assembly stays
        // deferred to the explicit `enable` action (PR8 lazy contract).
        let isRunning = await stub.isRunning
        XCTAssertFalse(isRunning, "init must remain a pure dependency-surface step")
    }

    func test_controllerInit_acceptsInjectedAgentBridge() async {
        let bridge = RecordingAgentBridge()
        _ = makeController(integration: NullRemoteIntegration(), bridge: bridge)
        let starts = await bridge.startCount
        let stops = await bridge.stopCount
        XCTAssertEqual(starts, 0, "init must not start the bridge")
        XCTAssertEqual(stops, 0, "init must not stop the bridge")
    }
}

private actor StubRemoteIntegration: RemoteIntegration {
    private(set) var isRunning = false
    private(set) var stopCount = 0
    private(set) var pushCount = 0

    func start() async throws {
        isRunning = true
    }

    func stop() async {
        stopCount += 1
        isRunning = false
    }

    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            token: "stub-token",
            macPublicKey: Data([0x01, 0x02, 0x03]),
            serviceName: "stub-mac",
            expiresAt: Date(timeIntervalSince1970: 9_999_999)
        )
    }

    func notifyPushReceived() async {
        pushCount += 1
    }

    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }

    func revokePairedDevice(id _: UUID) async throws {}

    func revokeAllPairedDevices() async throws -> [UUID] { [] }

    func resetPairingState() async throws {}

    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor RecordingLaunchControl: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []

    func bootstrap(plistURL: URL) async throws {
        bootstraps.append(plistURL)
    }

    func bootout(label: String) async throws {
        bootouts.append(label)
    }
}

private actor FailingLaunchControl: LaunchControlExecuting {
    func bootstrap(plistURL _: URL) async throws {
        throw LaunchAgentError.launchctlFailed(reason: "simulated")
    }

    func bootout(label _: String) async throws {
        // tolerate bootout in idempotency path
    }
}

private actor RecordingAgentBridge: RemoteAgentBridgeLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0

    func start() async { startCount += 1 }
    func stop() async { stopCount += 1 }
    func resetAgentState() async throws { resetCount += 1 }
}

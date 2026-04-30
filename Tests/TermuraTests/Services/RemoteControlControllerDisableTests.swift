import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR9 Step 5 — controller-layer `disable()` behaviour. Pinned in its
/// own file so the original `RemoteControlControllerTests.swift` stays
/// focused on init / enable / generateInvitation / general lifecycle.
/// Tests here cover only `disable` and its symmetric piece in
/// `enable` that persists the on-state to UserDefaults; `revokeAll`,
/// `revokeDevice`, and `resetPairings` live in their own files.
@MainActor
final class RemoteControlControllerDisableTests: XCTestCase {
    private var tempDir: URL!
    private var executor: OrderedLaunchControl!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var recorder: OrderingRecorder!
    private var helperResolver: StubHelperPathResolver!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-disable-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        recorder = OrderingRecorder()
        executor = OrderedLaunchControl(recorder: recorder)
        defaultsSuiteName = "termura-disable-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        helperResolver = try StubHelperPathResolver.makeBundledHelper(
            in: tempDir,
            name: "termura-remote-agent"
        )
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        recorder = nil
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        try await super.tearDown()
    }

    private func makeController(
        integration: any RemoteIntegration,
        bridge: any RemoteAgentBridgeLifecycle
    ) -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        return RemoteControlController(
            integration: integration,
            agentBridge: bridge,
            userDefaults: defaults,
            installer: installer,
            helperResolver: helperResolver
        )
    }

    // MARK: - Ordering

    func test_disable_runsBridgeStopThenIntegrationStopThenInstallerBootout() async {
        let integration = OrderedIntegration(recorder: recorder)
        let bridge = OrderedAgentBridge(recorder: recorder)
        let controller = makeController(integration: integration, bridge: bridge)
        // Pre-load the plist so uninstall has something to bootout.
        let metadata = RemoteAgentMetadata.default
        let preload = LaunchAgentInstaller.PlistConfig(
            label: metadata.label,
            executablePath: helperResolver.helperExecutableURL().path,
            runAtLoad: metadata.runAtLoad,
            machServices: metadata.machServices
        )
        try? await LaunchAgentInstaller(baseDirectory: tempDir, executor: executor).install(preload)
        await recorder.reset()

        await controller.disable()

        let steps = await recorder.steps
        // Filter to the three relevant events; bootstrap noise from the
        // pre-install above is excluded by `recorder.reset()`.
        let relevant = steps.filter {
            $0 == "bridge.stop" || $0 == "integration.stop" || $0 == "installer.bootout"
        }
        XCTAssertEqual(
            relevant,
            ["bridge.stop", "integration.stop", "installer.bootout"],
            "disable must run bridge.stop → integration.stop → installer.bootout in this exact order"
        )
    }

    // MARK: - State persistence

    func test_disable_persistsRemoteControlEnabledFalseToUserDefaults() async {
        // Pre-condition: defaults already says true (simulates a prior enable).
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let controller = makeController(
            integration: SilentIntegration(),
            bridge: SilentAgentBridge()
        )
        XCTAssertTrue(controller.isEnabled, "controller must start enabled given the persisted flag")

        await controller.disable()

        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(
            defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled),
            "disable must persist `false` to UserDefaults so a relaunch reflects the user's choice"
        )
    }

    func test_enable_persistsRemoteControlEnabledTrueToUserDefaults() async {
        let controller = makeController(
            integration: AlwaysSucceedsIntegration(),
            bridge: SilentAgentBridge()
        )

        await controller.enable()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertTrue(
            defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled),
            "enable must mirror disable's persistence so the on/off round-trip is closed"
        )
    }

    // MARK: - Soft failure: plist removal

    func test_disable_pListRemovalFails_stillWritesEnabledFalseAndSurfacesError() async throws {
        // The installer's uninstall path swallows `bootout` failures by
        // design and only throws if `FileManager.removeItem` itself
        // fails for a real reason. Reproduce that here by pre-creating
        // the plist file then chmod-ing the parent directory to `r-x`
        // so the unlink hits "operation not permitted".
        let plistURL = tempDir.appendingPathComponent("com.termura.remote-agent.plist")
        try Data().write(to: plistURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o500))],
            ofItemAtPath: tempDir.path
        )
        defer {
            // Restore write so tearDown can clean up tempDir cleanly.
            try? FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: tempDir.path
            )
        }

        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let controller = RemoteControlController(
            integration: SilentIntegration(),
            agentBridge: SilentAgentBridge(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: helperResolver
        )
        XCTAssertTrue(controller.isEnabled)

        await controller.disable()

        XCTAssertFalse(controller.isEnabled,
                       "uninstall failure must NOT block the disabled state — next enable will re-install idempotently")
        XCTAssertFalse(
            defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled),
            "uninstall failure must NOT block the persisted off state either"
        )
        XCTAssertNotNil(controller.lastError)
        XCTAssertTrue(
            (controller.lastError ?? "").contains("plist removal"),
            "lastError should reference the plist failure: '\(controller.lastError ?? "")'"
        )
    }

    // MARK: - Transient state cleanup

    func test_disable_clearsLatestInvitationJSON() async {
        let integration = AlwaysSucceedsIntegration()
        let controller = makeController(integration: integration, bridge: SilentAgentBridge())
        await controller.enable()
        await controller.generateInvitation()
        XCTAssertNotNil(controller.latestInvitationJSON, "precondition: invitation rendered")

        await controller.disable()

        XCTAssertNil(controller.latestInvitationJSON,
                     "disable must clear the rendered invitation; a stale token must not survive into the disabled state")
    }

    // MARK: - What disable does NOT do

    func test_disable_doesNotCallRevokeAllOnIntegration() async {
        let integration = SilentIntegration()
        let controller = makeController(integration: integration, bridge: SilentAgentBridge())

        await controller.disable()

        let revokeAllCalls = await integration.revokeAllCallCount
        let revokeSingleCalls = await integration.revokeSingleCallCount
        let resetPairingCalls = await integration.resetPairingCallCount
        XCTAssertEqual(revokeAllCalls, 0, "disable must not revoke any device")
        XCTAssertEqual(revokeSingleCalls, 0)
        XCTAssertEqual(resetPairingCalls, 0)
    }

    func test_disable_doesNotCallResetAgentStateOnBridge() async {
        let bridge = SilentAgentBridge()
        let controller = makeController(integration: SilentIntegration(), bridge: bridge)

        await controller.disable()

        let resetCount = await bridge.resetAgentStateCallCount
        XCTAssertEqual(resetCount, 0,
                       "disable must not call agent reset — that's resetPairings' job")
    }
}

// MARK: - Recording infrastructure

private actor OrderingRecorder {
    private(set) var steps: [String] = []
    func record(_ step: String) { steps.append(step) }
    func reset() { steps.removeAll() }
}

private actor OrderedIntegration: RemoteIntegration {
    private let recorder: OrderingRecorder
    var isRunning: Bool { false }

    init(recorder: OrderingRecorder) {
        self.recorder = recorder
    }

    func start() async throws { await recorder.record("integration.start") }
    func stop() async { await recorder.record("integration.stop") }

    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(token: "stub", macPublicKey: Data(), serviceName: "stub", expiresAt: Date())
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {}
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor OrderedAgentBridge: RemoteAgentBridgeLifecycle {
    private let recorder: OrderingRecorder

    init(recorder: OrderingRecorder) {
        self.recorder = recorder
    }

    func start() async { await recorder.record("bridge.start") }
    func stop() async { await recorder.record("bridge.stop") }
    func resetAgentState() async throws { await recorder.record("bridge.resetAgentState") }
}

private actor OrderedLaunchControl: LaunchControlExecuting {
    private let recorder: OrderingRecorder

    init(recorder: OrderingRecorder) {
        self.recorder = recorder
    }

    func bootstrap(plistURL _: URL) async throws {
        await recorder.record("installer.bootstrap")
    }

    func bootout(label _: String) async throws {
        await recorder.record("installer.bootout")
    }
}

/// Silent integration for tests that don't care about ordering — only
/// about counts and successful completion. Tracks call counts for the
/// PR9 surface so `disable` can be asserted as not touching them.
private actor SilentIntegration: RemoteIntegration {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var revokeSingleCallCount = 0
    private(set) var revokeAllCallCount = 0
    private(set) var resetPairingCallCount = 0
    var isRunning: Bool { false }

    func start() async throws { startCount += 1 }
    func stop() async { stopCount += 1 }
    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(token: "stub", macPublicKey: Data(), serviceName: "stub", expiresAt: Date())
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws { revokeSingleCallCount += 1 }
    func revokeAllPairedDevices() async throws -> [UUID] { revokeAllCallCount += 1; return [] }
    func resetPairingState() async throws { resetPairingCallCount += 1 }
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor SilentAgentBridge: RemoteAgentBridgeLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetAgentStateCallCount = 0

    func start() async { startCount += 1 }
    func stop() async { stopCount += 1 }
    func resetAgentState() async throws { resetAgentStateCallCount += 1 }
}

private actor AlwaysSucceedsIntegration: RemoteIntegration {
    var isRunning: Bool { false }
    func start() async throws {}
    func stop() async {}
    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            token: "ok",
            macPublicKey: Data([0xAA]),
            serviceName: "ok-mac",
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

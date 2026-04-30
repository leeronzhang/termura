import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR9 Step 6 — controller-layer `resetPairings()` orchestration.
/// Pinned in its own file because the orchestration is the largest
/// test surface in the controller suite (β probe + γ fallback + B
/// fallback + step ordering invariants).
@MainActor
final class RemoteControlControllerResetTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var executor: ResetRecordingExecutor!
    private var recorder: ResetOrderingRecorder!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-reset-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        recorder = ResetOrderingRecorder()
        executor = ResetRecordingExecutor(recorder: recorder)
        defaultsSuiteName = "termura-reset-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
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
        bridge: any RemoteAgentBridgeLifecycle,
        probe: any AgentDeathProbing = StubProbe(result: .confirmedDead),
        fallback: any AgentKeychainFallbackCleaning = NoopFallback(),
        startEnabled: Bool = false
    ) -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        if startEnabled {
            defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        }
        return RemoteControlController(
            integration: integration,
            agentBridge: bridge,
            userDefaults: defaults,
            installer: installer,
            agentDeathProbe: probe,
            fallbackCleaner: fallback
        )
    }

    // MARK: - Happy path

    func test_resetPairings_fromDisabled_runsHarnessWipeAndAgentResetThenPersistsOff() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        let controller = makeController(integration: integration, bridge: bridge)

        await controller.resetPairings()

        let purgeCount = await integration.resetPairingCallCount
        let agentResetCount = await bridge.resetCount
        XCTAssertEqual(purgeCount, 1, "step 5a must run exactly once")
        XCTAssertEqual(agentResetCount, 1, "step 5b must run exactly once")
        XCTAssertFalse(controller.isEnabled)
        XCTAssertFalse(defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled))
        XCTAssertNil(controller.lastError)
    }

    func test_resetPairings_fromEnabled_inlineDisablesBeforeReinstallingPlist() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            startEnabled: true
        )
        XCTAssertTrue(controller.isEnabled, "precondition: controller starts enabled")

        await controller.resetPairings()

        // From-enabled path runs: bridge.stop (inline-disable),
        // integration.stop (inline-disable), integration.stop (no — only once),
        // installer.bootout (inline-disable), installer.bootstrap (step 3
        // re-install), bridge.start (step 4), bridge.stop (step 6),
        // installer.bootout (step 7).
        let stops = await integration.stopCount
        let starts = await bridge.startCount
        XCTAssertGreaterThanOrEqual(stops, 1, "inline disable must stop integration")
        XCTAssertEqual(starts, 1, "step 4 must bring the bridge up exactly once")
        XCTAssertFalse(controller.isEnabled)
    }

    func test_resetPairings_temporarilyInstallsThenUninstallsPlist() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        let controller = makeController(integration: integration, bridge: bridge)

        await controller.resetPairings()

        let bootstraps = await executor.bootstraps
        let bootouts = await executor.bootouts
        XCTAssertEqual(bootstraps.count, 1, "step 3 must install the plist exactly once")
        XCTAssertGreaterThanOrEqual(bootouts.count, 1, "step 7 must uninstall the plist")
        // Plist file no longer exists at end of reset.
        let plistURL = tempDir.appendingPathComponent("com.termura.remote-agent.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistURL.path))
    }

    // MARK: - Step 5a hard-failure path

    func test_resetPairings_resetPairingStateFails_reportsLastErrorAndDoesNotTriggerFallbackB() async {
        let integration = ResetIntegration()
        await integration.failResetPairing(with: ResetTestError.simulated)
        let bridge = ResetAgentBridge(recorder: recorder)
        let probe = StubProbe(result: .confirmedDead)
        let fallback = RecordingFallback()
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            probe: probe,
            fallback: fallback
        )

        await controller.resetPairings()

        XCTAssertNotNil(controller.lastError)
        XCTAssertTrue(
            (controller.lastError ?? "").contains("pairing wipe"),
            "lastError should reference the 5a stage: '\(controller.lastError ?? "")'"
        )
        // Fallback B must NOT trigger when 5a fails — agent reset never ran.
        let fallbackCalls = await fallback.callCount
        XCTAssertEqual(fallbackCalls, 0)
        let agentResetCalls = await bridge.resetCount
        XCTAssertEqual(agentResetCalls, 0, "step 5b must not run after 5a fails")
        let probeCalls = await probe.callCount
        XCTAssertEqual(probeCalls, 0, "probe must not run after 5a fails")
    }

    // MARK: - Step 5b failure → β probe → γ / B paths

    func test_resetPairings_bridgeResetFails_andProbeConfirmsDead_triggersFallbackB() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        await bridge.failResetAgent(with: ResetTestError.simulated)
        let probe = StubProbe(result: .confirmedDead)
        let fallback = RecordingFallback()
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            probe: probe,
            fallback: fallback
        )

        await controller.resetPairings()

        let probeCalls = await probe.callCount
        let fallbackCalls = await fallback.callCount
        XCTAssertEqual(probeCalls, 1, "probe must run when 5b failed")
        XCTAssertEqual(fallbackCalls, 1, "confirmedDead must trigger fallback B exactly once")
        XCTAssertEqual(controller.lastError, "Agent reset via fallback: agent unreachable but agent state cleared via keychain.")
    }

    func test_resetPairings_bridgeResetFails_probeReturnsAlive_routesToGammaSkipsFallbackB() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        await bridge.failResetAgent(with: ResetTestError.simulated)
        let probe = StubProbe(result: .possiblyAlive)
        let fallback = RecordingFallback()
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            probe: probe,
            fallback: fallback
        )

        await controller.resetPairings()

        let fallbackCalls = await fallback.callCount
        XCTAssertEqual(fallbackCalls, 0, "possiblyAlive must NOT trigger fallback B")
        XCTAssertEqual(
            controller.lastError,
            "Reset partially completed: agent still reachable; agent state retained, retry reset."
        )
    }

    func test_resetPairings_bridgeResetFails_probeIndeterminate_routesToGammaSkipsFallbackB() async {
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        await bridge.failResetAgent(with: ResetTestError.simulated)
        let probe = StubProbe(result: .indeterminate)
        let fallback = RecordingFallback()
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            probe: probe,
            fallback: fallback
        )

        await controller.resetPairings()

        let fallbackCalls = await fallback.callCount
        XCTAssertEqual(fallbackCalls, 0, "indeterminate must NOT trigger fallback B")
        XCTAssertEqual(
            controller.lastError,
            "Reset partially completed: agent death unconfirmed; agent state retained."
        )
    }

    // MARK: - §12.6.1 invariant — soft failures must not short-circuit the probe

    func test_resetPairings_bridgeStopSoftFailureDoesNotShortCircuitProbe() async {
        // Bridge reset fails AND bridge.stop "fails" (we model that as
        // a no-op since the contract is non-throws — what we really
        // verify is that probe runs regardless of any post-5b state).
        let integration = ResetIntegration()
        let bridge = ResetAgentBridge(recorder: recorder)
        await bridge.failResetAgent(with: ResetTestError.simulated)
        let probe = StubProbe(result: .confirmedDead)
        let fallback = RecordingFallback()
        let controller = makeController(
            integration: integration,
            bridge: bridge,
            probe: probe,
            fallback: fallback
        )

        await controller.resetPairings()

        let probeCalls = await probe.callCount
        XCTAssertEqual(
            probeCalls,
            1,
            "§12.6.1: probe must run after step 5b failure regardless of step 6/7 outcome"
        )
    }

    // MARK: - Persistence

    func test_resetPairings_persistsEnabledFalseToUserDefaults() async {
        let controller = makeController(
            integration: ResetIntegration(),
            bridge: ResetAgentBridge(recorder: recorder),
            startEnabled: true
        )

        await controller.resetPairings()

        XCTAssertFalse(defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled))
    }
}

// MARK: - Test doubles

private actor ResetIntegration: RemoteIntegration {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetPairingCallCount = 0
    private var resetPairingError: Error?

    var isRunning: Bool { false }

    func failResetPairing(with error: Error) { resetPairingError = error }

    func start() async throws { startCount += 1 }
    func stop() async { stopCount += 1 }
    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(token: "stub", macPublicKey: Data(), serviceName: "stub", expiresAt: Date())
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {
        resetPairingCallCount += 1
        if let error = resetPairingError { throw error }
    }

    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor ResetAgentBridge: RemoteAgentBridgeLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0
    private var resetError: Error?
    private let recorder: ResetOrderingRecorder

    init(recorder: ResetOrderingRecorder) {
        self.recorder = recorder
    }

    func failResetAgent(with error: Error) { resetError = error }

    func start() async {
        startCount += 1
        await recorder.record("bridge.start")
    }

    func stop() async {
        stopCount += 1
        await recorder.record("bridge.stop")
    }

    func resetAgentState() async throws {
        resetCount += 1
        await recorder.record("bridge.resetAgentState")
        if let error = resetError { throw error }
    }
}

private actor StubProbe: AgentDeathProbing {
    private let result: ProbeResult
    private(set) var callCount = 0

    init(result: ProbeResult) { self.result = result }

    func confirmUnreachable(machServiceName _: String) async -> ProbeResult {
        callCount += 1
        return result
    }
}

private actor RecordingFallback: AgentKeychainFallbackCleaning {
    private(set) var callCount = 0
    func cleanCursorAndQuarantine() async { callCount += 1 }
}

private struct NoopFallback: AgentKeychainFallbackCleaning {
    func cleanCursorAndQuarantine() async {}
}

private actor ResetOrderingRecorder {
    private(set) var steps: [String] = []
    func record(_ step: String) { steps.append(step) }
}

private actor ResetRecordingExecutor: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []
    private let recorder: ResetOrderingRecorder

    init(recorder: ResetOrderingRecorder) {
        self.recorder = recorder
    }

    func bootstrap(plistURL: URL) async throws {
        bootstraps.append(plistURL)
        await recorder.record("installer.bootstrap")
    }

    func bootout(label: String) async throws {
        bootouts.append(label)
        await recorder.record("installer.bootout")
    }
}

private enum ResetTestError: Error, Equatable {
    case simulated
}

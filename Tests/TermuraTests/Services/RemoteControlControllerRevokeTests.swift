import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR9 Step 4 — controller-layer revoke behaviour. Pinned in its own
/// file so the original `RemoteControlControllerTests.swift` stays
/// focused on lifecycle (init, enable, disable, plist) and below the
/// 250-line soft cap. Tests here only cover `revokeAll` /
/// `revokeDevice`; transport teardown, `disable()`, and `resetPairings()`
/// land in later steps.
@MainActor
final class RemoteControlControllerRevokeTests: XCTestCase {
    private var tempDir: URL!
    private var executor: RecordingLaunchControlForRevoke!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-revoke-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        executor = RecordingLaunchControlForRevoke()
        defaultsSuiteName = "termura-revoke-tests-\(UUID().uuidString)"
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

    // MARK: - revokeAll

    func test_revokeAll_marksAllActiveDevices() async {
        let alice = PairedDeviceSummary(id: UUID(), nickname: "alice", pairedAt: Date(timeIntervalSince1970: 100))
        let bob = PairedDeviceSummary(id: UUID(), nickname: "bob", pairedAt: Date(timeIntervalSince1970: 200))
        let stub = RecordingRevokeIntegration()
        await stub.seed(active: [alice, bob])
        let controller = makeController(integration: stub)

        await controller.revokeAll()

        let calls = await stub.revokeAllCallCount
        XCTAssertEqual(calls, 1, "controller must call revokeAllPairedDevices exactly once")
        XCTAssertNil(controller.lastError, "happy path must clear lastError")
        // After revokeAll the harness flips revokedAt; verify the
        // refreshed list reflects that — every device shows revoked.
        XCTAssertEqual(controller.pairedDevices.count, 2)
        XCTAssertTrue(controller.pairedDevices.allSatisfy { !$0.isActive },
                      "post-revokeAll list must show every device as inactive")
    }

    func test_revokeAll_alreadyAllRevoked_isNoop() async {
        let stub = RecordingRevokeIntegration()
        await stub.seed(active: []) // empty active set — nothing to revoke
        let controller = makeController(integration: stub)

        await controller.revokeAll()

        XCTAssertNil(controller.lastError, "no active devices is not a failure")
        XCTAssertTrue(controller.pairedDevices.isEmpty)
        let calls = await stub.revokeAllCallCount
        XCTAssertEqual(calls, 1)
    }

    func test_revokeAll_totalFailure_writesGenericLastErrorAndDoesNotRefresh() async {
        // Step 4 follow-up: when the harness throws a non-partial error
        // (e.g. keychain unavailable, list load fails before any revoke
        // could happen), the controller writes a generic "Revoke all
        // failed: ..." message and does NOT refresh the device list.
        let alice = PairedDeviceSummary(id: UUID(), nickname: "alice", pairedAt: Date(timeIntervalSince1970: 100))
        let stub = RecordingRevokeIntegration()
        await stub.seed(active: [alice])
        await stub.failRevokeAllTotally(with: TotalFailureError.simulated)
        let controller = makeController(integration: stub)

        // Pre-populate paired devices so we can verify they don't get
        // overwritten by a refresh that should NOT fire.
        await controller.refreshDevicesAndAudit()
        let initialCount = controller.pairedDevices.count
        XCTAssertEqual(initialCount, 1)
        let listCallsBefore = await stub.listCallCount

        await controller.revokeAll()

        XCTAssertNotNil(controller.lastError)
        XCTAssertTrue(
            (controller.lastError ?? "").hasPrefix("Revoke all failed:"),
            "lastError should use the generic prefix: '\(controller.lastError ?? "")'"
        )
        let listCallsAfter = await stub.listCallCount
        XCTAssertEqual(
            listCallsAfter,
            listCallsBefore,
            "total failure must NOT refresh devices/audit (refresh would have called listPairedDevices)"
        )
    }

    func test_revokeAll_partialFailure_continuesAndReportsFailedIds() async {
        let alice = PairedDeviceSummary(id: UUID(), nickname: "alice", pairedAt: Date(timeIntervalSince1970: 100))
        let bob = PairedDeviceSummary(id: UUID(), nickname: "bob", pairedAt: Date(timeIntervalSince1970: 200))
        let charlie = PairedDeviceSummary(id: UUID(), nickname: "charlie", pairedAt: Date(timeIntervalSince1970: 300))
        let stub = RecordingRevokeIntegration()
        await stub.seed(active: [alice, bob, charlie])
        await stub.failRevokeAll(with: [bob.id, charlie.id])
        let controller = makeController(integration: stub)

        await controller.revokeAll()

        XCTAssertNotNil(controller.lastError, "partial failure must surface to UI")
        let lastError = controller.lastError ?? ""
        XCTAssertTrue(
            lastError.contains("2 device") || lastError.contains("2 devices"),
            "lastError should mention failed count: '\(lastError)'"
        )
        // The refreshed list should still reflect the partial outcome:
        // alice (success) is now inactive, bob+charlie (failures) stay
        // active because their persistence write didn't land.
        XCTAssertEqual(controller.pairedDevices.count, 3)
        let bobEntry = controller.pairedDevices.first { $0.id == bob.id }
        let aliceEntry = controller.pairedDevices.first { $0.id == alice.id }
        XCTAssertEqual(aliceEntry?.isActive, false, "alice's revoke succeeded")
        XCTAssertEqual(bobEntry?.isActive, true, "bob's revoke failed — must remain active")
    }

    func test_revokeAll_doesNotTouchTransportsOrPlist() async {
        let alice = PairedDeviceSummary(id: UUID(), nickname: "alice", pairedAt: Date(timeIntervalSince1970: 100))
        let stub = RecordingRevokeIntegration()
        await stub.seed(active: [alice])
        let bridge = RecordingRevokeAgentBridge()
        let controller = makeController(integration: stub, bridge: bridge)

        await controller.revokeAll()

        let stopCount = await stub.stopCount
        let startCount = await stub.startCount
        XCTAssertEqual(stopCount, 0, "revokeAll must not stop the integration")
        XCTAssertEqual(startCount, 0, "revokeAll must not start the integration")

        let bridgeStarts = await bridge.startCount
        let bridgeStops = await bridge.stopCount
        let bridgeResets = await bridge.resetCount
        XCTAssertEqual(bridgeStarts, 0)
        XCTAssertEqual(bridgeStops, 0)
        XCTAssertEqual(bridgeResets, 0)

        let bootouts = await executor.bootouts
        let bootstraps = await executor.bootstraps
        XCTAssertTrue(bootouts.isEmpty, "revokeAll must not run launchctl bootout")
        XCTAssertTrue(bootstraps.isEmpty, "revokeAll must not run launchctl bootstrap")
    }

    // MARK: - revokeDevice (Step 1 idempotency adaptation)

    func test_revokeDevice_alreadyRevokedIdFlowsThroughWithoutError() async {
        let stub = RecordingRevokeIntegration()
        let controller = makeController(integration: stub)
        // Pre-seed lastError to verify success clears it.
        await controller.revokeAll() // no-op (empty seed) but normalizes lastError = nil
        XCTAssertNil(controller.lastError)

        // Step 1 made `PairingService.revoke(deviceId:)` a silent no-op
        // for already-revoked ids — the integration succeeds without
        // throwing `notFound`, and the controller must not surface a
        // phantom "Revoke failed" error on the UI.
        await controller.revokeDevice(id: UUID())
        XCTAssertNil(
            controller.lastError,
            "Step 1's idempotent revoke must not surface a controller-level error"
        )
        let revokeCalls = await stub.revokeSingleCallCount
        XCTAssertEqual(revokeCalls, 1)
    }
}

// MARK: - Test doubles

/// Records revoke-flow calls and supports configurable failure modes
/// for `revokeAllPairedDevices`. Maintains a small in-memory list so
/// `listPairedDevices` reflects the post-revoke state — the controller
/// reads it via `refreshDevicesAndAudit`.
private actor RecordingRevokeIntegration: RemoteIntegration {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var revokeSingleCallCount = 0
    private(set) var revokeAllCallCount = 0
    private(set) var listCallCount = 0
    private(set) var revokedSingleIds: [UUID] = []

    private var devices: [PairedDeviceSummary] = []
    private var revokeAllFailureIds: [UUID]?
    private var revokeAllTotalFailureError: Error?
    private let revokedAtFixed = Date(timeIntervalSince1970: 1_000_000)

    var isRunning: Bool { false }

    func seed(active devices: [PairedDeviceSummary]) {
        self.devices = devices
    }

    func failRevokeAll(with failedIds: [UUID]) {
        revokeAllFailureIds = failedIds
    }

    func failRevokeAllTotally(with error: Error) {
        revokeAllTotalFailureError = error
    }

    func start() async throws {
        startCount += 1
    }

    func stop() async {
        stopCount += 1
    }

    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(
            token: "stub",
            macPublicKey: Data([0x01]),
            serviceName: "stub-mac",
            expiresAt: Date(timeIntervalSince1970: 9_999_999)
        )
    }

    func notifyPushReceived() async {}

    func listPairedDevices() async throws -> [PairedDeviceSummary] {
        listCallCount += 1
        return devices
    }

    func revokePairedDevice(id: UUID) async throws {
        revokeSingleCallCount += 1
        revokedSingleIds.append(id)
        // Mirror Step 1 idempotency: no throw even for unknown / already-revoked ids.
    }

    func revokeAllPairedDevices() async throws -> [UUID] {
        revokeAllCallCount += 1
        if let error = revokeAllTotalFailureError {
            throw error
        }
        let activeBefore = devices.filter(\.isActive)
        guard let failedIds = revokeAllFailureIds else {
            // Happy path: flip every active device to revoked.
            devices = devices.map { device in
                device.isActive
                    ? PairedDeviceSummary(id: device.id, nickname: device.nickname, pairedAt: device.pairedAt, revokedAt: revokedAtFixed)
                    : device
            }
            return activeBefore.map(\.id)
        }
        // Partial-failure path: revoke only the ids that aren't on
        // the failure list, then throw with the failed ids.
        devices = devices.map { device in
            if !device.isActive { return device }
            if failedIds.contains(device.id) { return device }
            return PairedDeviceSummary(
                id: device.id,
                nickname: device.nickname,
                pairedAt: device.pairedAt,
                revokedAt: revokedAtFixed
            )
        }
        throw RemoteAdapterError.partialRevokeAllFailed(failed: failedIds)
    }

    func resetPairingState() async throws {}

    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

private actor RecordingRevokeAgentBridge: RemoteAgentBridgeLifecycle {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var resetCount = 0

    func start() async { startCount += 1 }
    func stop() async { stopCount += 1 }
    func resetAgentState() async throws { resetCount += 1 }
}

private actor RecordingLaunchControlForRevoke: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []

    func bootstrap(plistURL: URL) async throws {
        bootstraps.append(plistURL)
    }

    func bootout(label: String) async throws {
        bootouts.append(label)
    }
}

private enum TotalFailureError: Error, Equatable {
    case simulated
}

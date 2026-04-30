import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR10 Step 2 — controller-layer helper-bundling health check.
/// `enable()` must validate the resolver-derived helper binary
/// (file exists + executable bit) before bootstrapping launchd, so
/// that a build that shipped without `Contents/Helpers/termura-remote-agent`
/// fails closed instead of writing a plist that points at nothing.
@MainActor
final class RemoteControlControllerEnableHelperTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var executor: RecordingLaunchControlForEnableHelper!
    private var integration: SilentEnableHelperIntegration!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-enable-helper-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        executor = RecordingLaunchControlForEnableHelper()
        integration = SilentEnableHelperIntegration()
        defaultsSuiteName = "termura-enable-helper-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        executor = nil
        integration = nil
        defaults?.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        defaultsSuiteName = nil
        try await super.tearDown()
    }

    // MARK: - Helper present

    func test_enable_helperPresentAndExecutable_installsPlistAndPersistsEnabled() async throws {
        let resolver = try StubHelperPathResolver.makeBundledHelper(in: tempDir, name: "termura-remote-agent")
        let controller = makeController(resolver: resolver)

        await controller.enable()

        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastError)
        let bootstraps = await executor.bootstraps
        let startCount = await integration.startCount
        let stopCount = await integration.stopCount
        XCTAssertEqual(bootstraps.count, 1, "install must run when helper validation passed")
        XCTAssertEqual(startCount, 1, "integration must remain started; no rollback on the happy path")
        XCTAssertEqual(stopCount, 0)
        XCTAssertTrue(defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled))
    }

    func test_enable_helperPresent_runtimePlistConfigPointsAtResolvedPath() async throws {
        let resolver = try StubHelperPathResolver.makeBundledHelper(in: tempDir, name: "termura-remote-agent")
        let controller = makeController(resolver: resolver)

        await controller.enable()

        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let installedPath = installer.installedExecutablePath(label: RemoteAgentMetadata.default.label)
        XCTAssertEqual(
            installedPath, resolver.helperExecutableURL().path,
            "the on-disk plist must record the resolver-derived path, not a placeholder"
        )
    }

    // MARK: - Helper missing

    func test_enable_helperNotBundled_failsClosedAndStopsIntegration() async throws {
        let missingPath = tempDir.appendingPathComponent("termura-remote-agent-missing").path
        let resolver = StubHelperPathResolver(path: missingPath)
        let controller = makeController(resolver: resolver)

        await controller.enable()

        XCTAssertFalse(controller.isEnabled)
        XCTAssertNotNil(controller.lastError)
        let lastError = try XCTUnwrap(controller.lastError)
        XCTAssertTrue(
            lastError.contains("not bundled") && lastError.contains(missingPath),
            "lastError must surface helperNotBundled with the resolved path: '\(lastError)'"
        )
        let bootstraps = await executor.bootstraps
        let stopCount = await integration.stopCount
        XCTAssertTrue(bootstraps.isEmpty, "install must not run when helper is missing")
        XCTAssertEqual(stopCount, 1, "integration must be rolled back when validation fails")
        XCTAssertFalse(defaults.bool(forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled))
    }

    // MARK: - Helper non-executable

    func test_enable_helperPresentButNotExecutable_failsClosedAndStopsIntegration() async throws {
        let helperPath = tempDir.appendingPathComponent("termura-remote-agent").path
        try Data([0x00]).write(to: URL(fileURLWithPath: helperPath))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: helperPath
        )
        let resolver = StubHelperPathResolver(path: helperPath)
        let controller = makeController(resolver: resolver)

        await controller.enable()

        XCTAssertFalse(controller.isEnabled)
        let lastError = try XCTUnwrap(controller.lastError)
        XCTAssertTrue(
            lastError.contains("not executable") && lastError.contains(helperPath),
            "lastError must surface helperNotExecutable with the resolved path: '\(lastError)'"
        )
        let bootstraps = await executor.bootstraps
        let stopCount = await integration.stopCount
        XCTAssertTrue(bootstraps.isEmpty)
        XCTAssertEqual(stopCount, 1)
    }

    // MARK: - Order: integration first, then validation

    func test_enable_integrationFailsBeforeValidation_doesNotInvokeResolver() async {
        // If integration.start() throws, the helper validation must NOT run
        // — the controller can't have started transports it can't stop, so
        // we don't need to reason about helper state in that branch.
        let resolver = TrackingResolver(path: tempDir.appendingPathComponent("agent").path)
        let failing = AlwaysFailingIntegration()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let controller = RemoteControlController(
            integration: failing,
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: resolver
        )

        await controller.enable()

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(
            resolver.callCount, 0,
            "validation must not run when integration startup already failed"
        )
    }

    // MARK: - Helpers

    private func makeController(resolver: any RemoteHelperPathResolving) -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        return RemoteControlController(
            integration: integration,
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: resolver
        )
    }
}

private actor RecordingLaunchControlForEnableHelper: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []

    func bootstrap(plistURL: URL) async throws { bootstraps.append(plistURL) }
    func bootout(label: String) async throws { bootouts.append(label) }
}

private actor SilentEnableHelperIntegration: RemoteIntegration {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    var isRunning: Bool { false }

    func start() async throws { startCount += 1 }
    func stop() async { stopCount += 1 }

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

private actor AlwaysFailingIntegration: RemoteIntegration {
    var isRunning: Bool { false }
    func start() async throws { throw NSError(domain: "test", code: 1) }
    func stop() async {}
    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(token: "x", macPublicKey: Data(), serviceName: "x", expiresAt: Date())
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {}
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

/// Counts how often the resolver is consulted so we can assert the
/// integration-failure branch never reaches helper validation.
private final class TrackingResolver: RemoteHelperPathResolving, @unchecked Sendable {
    let path: String
    private let lock = NSLock()
    private var _callCount = 0
    var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    init(path: String) { self.path = path }

    func helperExecutableURL() -> URL {
        lock.lock(); _callCount += 1; lock.unlock()
        return URL(fileURLWithPath: path)
    }
}

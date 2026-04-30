import Foundation
@testable import Termura
import TermuraRemoteProtocol
import XCTest

/// PR10 Step 3 — controller-layer `reinstallIfNeeded()` behaviour.
/// Pinned in its own file so the original `EnableHelperTests` stays
/// focused on the install-time fail-closed path.
@MainActor
final class RemoteControlControllerReinstallTests: XCTestCase {
    private var tempDir: URL!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var executor: ReinstallRecordingExecutor!
    private var helperResolver: StubHelperPathResolver!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-reinstall-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        executor = ReinstallRecordingExecutor()
        defaultsSuiteName = "termura-reinstall-tests-\(UUID().uuidString)"
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

    // MARK: - Disabled

    func test_reinstallIfNeeded_whenDisabled_isNoop() async {
        let controller = makeController()
        XCTAssertFalse(controller.isEnabled)

        await controller.reinstallIfNeeded()

        let bootstraps = await executor.bootstraps
        XCTAssertTrue(bootstraps.isEmpty, "disabled controller must never reinstall")
        XCTAssertNil(controller.lastError)
    }

    // MARK: - Enabled, all aligned

    func test_reinstallIfNeeded_whenEnabledPathAndFingerprintMatch_isNoop() async {
        let controller = makeController()
        await controller.enable()
        let bootstrapsAfterEnable = await executor.bootstraps
        XCTAssertEqual(bootstrapsAfterEnable.count, 1, "precondition: enable installed once")

        await controller.reinstallIfNeeded()

        let finalBootstraps = await executor.bootstraps
        XCTAssertEqual(finalBootstraps.count, 1, "no second install when nothing drifted")
    }

    // MARK: - Path drift

    func test_reinstallIfNeeded_whenPlistPathDoesNotMatchResolver_reinstalls() async throws {
        let controller = makeController()
        // Bring the controller up the normal way so isEnabled is true and
        // the recorded fingerprint matches the current helper file.
        await controller.enable()
        XCTAssertTrue(controller.isEnabled, "precondition: controller is enabled after enable()")

        // Now overwrite the on-disk plist with a stale path so the
        // matchesInstalled check fails on the next reinstallIfNeeded call.
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let staleConfig = LaunchAgentInstaller.PlistConfig(
            label: RemoteAgentMetadata.default.label,
            executablePath: "/Applications/OldTermura.app/Contents/Helpers/termura-remote-agent",
            runAtLoad: true,
            machServices: ["com.termura.remote-agent"]
        )
        try await installer.install(staleConfig)
        await executor.reset()

        await controller.reinstallIfNeeded()

        let bootstraps = await executor.bootstraps
        XCTAssertEqual(bootstraps.count, 1, "path drift must trigger one reinstall")
        let installed = installer.installedExecutablePath(label: RemoteAgentMetadata.default.label)
        XCTAssertEqual(
            installed, helperResolver.helperExecutableURL().path,
            "post-reinstall plist must record the resolver-derived path"
        )
    }

    // MARK: - Fingerprint drift

    func test_reinstallIfNeeded_whenFingerprintDiffersFromLastInstall_reinstalls() async throws {
        let controller = makeController()
        await controller.enable()
        await executor.reset()

        // Simulate helper-binary upgrade: rewrite the helper file with
        // different content so its size + mtime differ from the recorded
        // fingerprint.
        let helperURL = URL(fileURLWithPath: helperResolver.helperExecutableURL().path)
        try Data(repeating: 0xFF, count: 4096).write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )

        await controller.reinstallIfNeeded()

        let bootstraps = await executor.bootstraps
        XCTAssertEqual(bootstraps.count, 1, "fingerprint drift must trigger one reinstall")
    }

    // MARK: - Helper missing

    func test_reinstallIfNeeded_whenHelperMissing_doesNotReinstallAndDoesNotAutoDisable() async throws {
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let missingPath = tempDir.appendingPathComponent("never-existed").path
        let resolver = StubHelperPathResolver(path: missingPath)
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let controller = RemoteControlController(
            integration: NullRemoteIntegration(),
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: resolver
        )
        XCTAssertTrue(controller.isEnabled, "precondition: persisted on/off says enabled")

        await controller.reinstallIfNeeded()

        let bootstraps = await executor.bootstraps
        XCTAssertTrue(bootstraps.isEmpty, "must not install when helper file is missing")
        XCTAssertTrue(
            controller.isEnabled,
            "isEnabled reflects user intent; reinstall must not auto-disable on missing helper"
        )
        let lastError = try XCTUnwrap(controller.lastError)
        XCTAssertTrue(lastError.contains(missingPath), "lastError must surface the missing path")
    }

    // MARK: - Stale helper error cleared on recovery

    func test_reinstallIfNeeded_whenAlignedAndPriorHelperErrorPresent_clearsLastError() async throws {
        // Phase 1: persisted enabled + helper missing → reinstallIfNeeded
        // sets a helper-class error.
        defaults.set(true, forKey: AppConfig.UserDefaultsKeys.remoteControlEnabled)
        let helperPath = tempDir.appendingPathComponent("future-helper").path
        let resolver = StubHelperPathResolver(path: helperPath)
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let controller = RemoteControlController(
            integration: AlwaysSucceedsReinstallIntegration(),
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: resolver
        )
        await controller.reinstallIfNeeded()
        XCTAssertNotNil(controller.lastError, "precondition: missing helper produced an error")
        XCTAssertEqual(controller.lastErrorOrigin, .helperHealth)

        // Phase 2: helper recovers + plist already matches resolver path
        // + fingerprint already recorded → reinstallIfNeeded should
        // observe an aligned state and clear the stale helper-class error.
        try Data([0x01]).write(to: URL(fileURLWithPath: helperPath))
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperPath
        )
        let alignedConfig = LaunchAgentInstaller.PlistConfig(
            label: RemoteAgentMetadata.default.label,
            executablePath: helperPath,
            runAtLoad: true,
            machServices: ["com.termura.remote-agent"]
        )
        try await installer.install(alignedConfig)
        controller.recordFingerprintAfterInstall()
        await executor.reset()

        await controller.reinstallIfNeeded()

        let bootstraps = await executor.bootstraps
        XCTAssertTrue(bootstraps.isEmpty, "aligned state must not trigger another install")
        XCTAssertNil(controller.lastError, "stale helper-class error must be cleared on recovery")
        XCTAssertNil(controller.lastErrorOrigin)
    }

    func test_reinstallIfNeeded_whenAligned_doesNotClearOtherOriginErrors() async throws {
        // Bring the controller up cleanly first so reinstallIfNeeded sees
        // a fully aligned state when called below.
        let controller = makeController()
        await controller.enable()
        XCTAssertTrue(controller.isEnabled)
        XCTAssertNil(controller.lastError, "precondition: enable left no error")

        // Simulate an unrelated error landing on lastError (e.g. a
        // generateInvitation failure). reinstallIfNeeded must not
        // silently erase it just because helper health looks OK.
        controller.setOtherError("Failed to render invitation")
        XCTAssertEqual(controller.lastErrorOrigin, .other)

        await controller.reinstallIfNeeded()

        XCTAssertEqual(
            controller.lastError, "Failed to render invitation",
            "non-helper errors are not in reinstall's ownership and must be preserved"
        )
        XCTAssertEqual(controller.lastErrorOrigin, .other)
    }

    // MARK: - helperHealth diagnostic surface

    func test_helperHealth_returnsResolverPathAndFingerprintAfterEnable() async {
        let controller = makeController()
        await controller.enable()
        let health = controller.helperHealth()
        XCTAssertEqual(health.resolvedExecutablePath, helperResolver.helperExecutableURL().path)
        XCTAssertTrue(health.resolvedExists)
        XCTAssertEqual(health.installedExecutablePath, helperResolver.helperExecutableURL().path)
        XCTAssertTrue(health.matchesInstalled)
        XCTAssertTrue(
            health.fingerprintMatchesLastInstall,
            "post-enable fingerprint must match the freshly recorded one"
        )
    }

    func test_helperHealth_whenHelperMissing_resolvedExistsIsFalse() {
        let resolver = StubHelperPathResolver(path: tempDir.appendingPathComponent("nope").path)
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let controller = RemoteControlController(
            integration: AlwaysSucceedsReinstallIntegration(),
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: resolver
        )

        let health = controller.helperHealth()

        XCTAssertFalse(health.resolvedExists)
        XCTAssertNil(health.installedExecutablePath, "no plist installed yet")
        XCTAssertFalse(health.matchesInstalled)
    }

    // MARK: - Helpers

    private func makeController() -> RemoteControlController {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        return RemoteControlController(
            integration: AlwaysSucceedsReinstallIntegration(),
            agentBridge: NullRemoteAgentBridgeLifecycle(),
            userDefaults: defaults,
            installer: installer,
            helperResolver: helperResolver
        )
    }
}

private actor ReinstallRecordingExecutor: LaunchControlExecuting {
    private(set) var bootstraps: [URL] = []
    private(set) var bootouts: [String] = []

    func bootstrap(plistURL: URL) async throws { bootstraps.append(plistURL) }
    func bootout(label: String) async throws { bootouts.append(label) }
    func reset() {
        bootstraps.removeAll()
        bootouts.removeAll()
    }
}

private actor AlwaysSucceedsReinstallIntegration: RemoteIntegration {
    var isRunning: Bool { false }
    func start() async throws {}
    func stop() async {}
    func issueInvitation() async throws -> PairingInvitation {
        PairingInvitation(token: "ok", macPublicKey: Data(), serviceName: "ok", expiresAt: Date())
    }

    func notifyPushReceived() async {}
    func listPairedDevices() async throws -> [PairedDeviceSummary] { [] }
    func revokePairedDevice(id _: UUID) async throws {}
    func revokeAllPairedDevices() async throws -> [UUID] { [] }
    func resetPairingState() async throws {}
    func auditLog() async throws -> [RemoteAuditEntry] { [] }
}

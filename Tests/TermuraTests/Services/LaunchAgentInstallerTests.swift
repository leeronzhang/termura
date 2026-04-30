import Foundation
@testable import Termura
import XCTest

final class LaunchAgentInstallerTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-launch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    func testPlistRendersCoreKeys() throws {
        let config = LaunchAgentInstaller.PlistConfig(
            label: "com.termura.remote-agent",
            executablePath: "/usr/local/bin/termura-remote-agent"
        )
        let data = try LaunchAgentInstaller.renderPlistData(config: config)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try XCTUnwrap(parsed as? [String: Any])
        XCTAssertEqual(dict["Label"] as? String, "com.termura.remote-agent")
        XCTAssertEqual(dict["RunAtLoad"] as? Bool, true)
        XCTAssertEqual(dict["KeepAlive"] as? Bool, false)
        XCTAssertEqual(dict["LimitLoadToSessionType"] as? String, "Aqua")
        let args = try XCTUnwrap(dict["ProgramArguments"] as? [String])
        XCTAssertEqual(args, ["/usr/local/bin/termura-remote-agent"])
    }

    func test_defaultRemoteAgent_includesMachServicesEntry() throws {
        // PR9 Step 5.1 — without this entry launchd doesn't register
        // the mach service name, so `NSXPCConnection(machServiceName:)`
        // from the main app would always invalidate. Both the auto-
        // connector and the resetPairings β-probe depend on the entry.
        let data = try LaunchAgentInstaller.renderPlistData(
            config: .defaultRemoteAgent
        )
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        let dict = try XCTUnwrap(parsed as? [String: Any])
        let machServices = try XCTUnwrap(
            dict["MachServices"] as? [String: Bool],
            "defaultRemoteAgent must declare a MachServices dictionary"
        )
        XCTAssertEqual(
            machServices,
            ["com.termura.remote-agent": true],
            "the only registered mach name must be the agent's bootstrap label"
        )
    }

    func testInstallWritesPlistAndCallsBootstrap() async throws {
        let executor = RecordingLaunchControl()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let config = LaunchAgentInstaller.PlistConfig(
            label: "com.termura.remote-agent",
            executablePath: "/usr/local/bin/agent"
        )
        try await installer.install(config)
        XCTAssertTrue(installer.isInstalled(label: config.label))
        let plistURL = installer.url(for: config.label)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))
        let bootstraps = await executor.bootstraps
        XCTAssertEqual(bootstraps, [plistURL])
    }

    func testInstallIsIdempotentRebootouts() async throws {
        let executor = RecordingLaunchControl()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let config = LaunchAgentInstaller.PlistConfig(
            label: "com.termura.remote-agent",
            executablePath: "/usr/local/bin/agent"
        )
        try await installer.install(config)
        try await installer.install(config)
        let bootouts = await executor.bootouts
        let bootstraps = await executor.bootstraps
        XCTAssertEqual(bootouts.count, 2, "second install should bootout the previous load")
        XCTAssertEqual(bootstraps.count, 2)
    }

    func testUninstallRemovesPlistAndCallsBootout() async throws {
        let executor = RecordingLaunchControl()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        let config = LaunchAgentInstaller.PlistConfig(
            label: "com.termura.remote-agent",
            executablePath: "/usr/local/bin/agent"
        )
        try await installer.install(config)
        try await installer.uninstall(label: config.label)
        XCTAssertFalse(installer.isInstalled(label: config.label))
        let bootouts = await executor.bootouts
        XCTAssertTrue(bootouts.contains(config.label))
    }

    func testUninstallMissingIsNoop() async throws {
        let executor = RecordingLaunchControl()
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: executor)
        // No install — should not throw.
        try await installer.uninstall(label: "com.termura.remote-agent")
        XCTAssertFalse(installer.isInstalled(label: "com.termura.remote-agent"))
    }

    // MARK: - installedExecutablePath

    func test_installedExecutablePath_missingPlist_returnsNil() {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: RecordingLaunchControl())
        XCTAssertNil(installer.installedExecutablePath(label: "com.termura.remote-agent"))
    }

    func test_installedExecutablePath_returnsFirstProgramArgument() async throws {
        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: RecordingLaunchControl())
        let config = LaunchAgentInstaller.PlistConfig(
            label: "com.termura.remote-agent",
            executablePath: "/Applications/Termura.app/Contents/Helpers/termura-remote-agent"
        )
        try await installer.install(config)

        let installed = installer.installedExecutablePath(label: config.label)
        XCTAssertEqual(installed, "/Applications/Termura.app/Contents/Helpers/termura-remote-agent")
    }

    func test_installedExecutablePath_emptyProgramArguments_returnsNil() throws {
        let label = "com.termura.remote-agent"
        let plistURL = tempDir.appendingPathComponent("\(label).plist")
        let dict: [String: Any] = ["Label": label, "ProgramArguments": [String]()]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: plistURL)

        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: RecordingLaunchControl())
        XCTAssertNil(installer.installedExecutablePath(label: label))
    }

    func test_installedExecutablePath_malformedPlist_returnsNil() throws {
        let label = "com.termura.remote-agent"
        let plistURL = tempDir.appendingPathComponent("\(label).plist")
        try Data("not a real plist".utf8).write(to: plistURL)

        let installer = LaunchAgentInstaller(baseDirectory: tempDir, executor: RecordingLaunchControl())
        XCTAssertNil(installer.installedExecutablePath(label: label))
    }
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

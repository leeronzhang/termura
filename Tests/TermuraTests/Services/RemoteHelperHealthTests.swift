import Foundation
@testable import Termura
import XCTest

final class RemoteHelperHealthTests: XCTestCase {
    private var tempDir: URL!
    private var helperPath: String { tempDir.appendingPathComponent("termura-remote-agent").path }
    private var launchAgentsDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-health-tests-\(UUID().uuidString)")
        launchAgentsDir = tempDir.appendingPathComponent("LaunchAgents")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Inspect

    func test_helperPresentAndPlistMatches_allTrue() async throws {
        let installer = makeInstaller()
        let resolver = StubResolver(path: helperPath)
        try writeHelper(content: Data([0x01, 0x02, 0x03]))
        try await installer.install(.makeFor(label: "com.example.agent", executablePath: helperPath))

        let health = RemoteHelperHealth.inspect(
            resolver: resolver,
            installer: installer,
            label: "com.example.agent"
        )

        XCTAssertEqual(health.resolvedExecutablePath, helperPath)
        XCTAssertTrue(health.resolvedExists)
        XCTAssertEqual(health.installedExecutablePath, helperPath)
        XCTAssertTrue(health.matchesInstalled)
        XCTAssertTrue(health.fingerprintMatchesLastInstall)
    }

    func test_helperExistsButPlistMissing_installedNilAndDoesNotMatch() throws {
        let installer = makeInstaller()
        let resolver = StubResolver(path: helperPath)
        try writeHelper(content: Data([0x01]))

        let health = RemoteHelperHealth.inspect(
            resolver: resolver,
            installer: installer,
            label: "com.example.agent"
        )

        XCTAssertTrue(health.resolvedExists)
        XCTAssertNil(health.installedExecutablePath)
        XCTAssertFalse(health.matchesInstalled)
        XCTAssertTrue(health.fingerprintMatchesLastInstall, "no recorded fingerprint => no mismatch")
    }

    func test_helperMissingButPlistInstalled_resolvedExistsFalse() async throws {
        let installer = makeInstaller()
        let resolver = StubResolver(path: helperPath)
        try await installer.install(.makeFor(label: "com.example.agent", executablePath: helperPath))
        // Note: never wrote helperPath, so the plist points at a path with no file.

        let health = RemoteHelperHealth.inspect(
            resolver: resolver,
            installer: installer,
            label: "com.example.agent"
        )

        XCTAssertFalse(health.resolvedExists)
        XCTAssertEqual(health.installedExecutablePath, helperPath)
        XCTAssertTrue(health.matchesInstalled, "paths still equal even if file is gone")
    }

    func test_fingerprintMismatch_flipsLastFlagFalse() async throws {
        let installer = makeInstaller()
        let resolver = StubResolver(path: helperPath)
        try writeHelper(content: Data([0x01, 0x02, 0x03, 0x04]))
        try await installer.install(.makeFor(label: "com.example.agent", executablePath: helperPath))
        let stale = RemoteHelperFingerprint(
            path: helperPath,
            size: 999_999,
            mtime: Date(timeIntervalSince1970: 0)
        )

        let health = RemoteHelperHealth.inspect(
            resolver: resolver,
            installer: installer,
            label: "com.example.agent",
            lastInstalledFingerprint: stale
        )

        XCTAssertFalse(health.fingerprintMatchesLastInstall)
        XCTAssertTrue(health.matchesInstalled)
    }

    func test_fingerprintMissingButRecorded_flipsLastFlagFalse() throws {
        let installer = makeInstaller()
        let resolver = StubResolver(path: helperPath)
        let stale = RemoteHelperFingerprint(
            path: helperPath,
            size: 100,
            mtime: Date(timeIntervalSince1970: 0)
        )
        // Helper file never written.

        let health = RemoteHelperHealth.inspect(
            resolver: resolver,
            installer: installer,
            label: "com.example.agent",
            lastInstalledFingerprint: stale
        )

        XCTAssertFalse(
            health.fingerprintMatchesLastInstall,
            "Last install was recorded but the file is gone — treat as mismatch so reinstall fires."
        )
    }

    // MARK: - Fingerprint.read

    func test_fingerprintRead_returnsNilForMissingFile() {
        let value = RemoteHelperFingerprint.read(at: helperPath)
        XCTAssertNil(value)
    }

    func test_fingerprintRead_capturesSizeAndMtime() throws {
        try writeHelper(content: Data(repeating: 0xAB, count: 17))
        let value = try XCTUnwrap(RemoteHelperFingerprint.read(at: helperPath))
        XCTAssertEqual(value.path, helperPath)
        XCTAssertEqual(value.size, 17)
    }

    // MARK: - Helpers

    private func makeInstaller() -> LaunchAgentInstaller {
        LaunchAgentInstaller(baseDirectory: launchAgentsDir, executor: NoopExecutor())
    }

    private func writeHelper(content: Data) throws {
        try content.write(to: URL(fileURLWithPath: helperPath))
    }
}

private struct StubResolver: RemoteHelperPathResolving {
    let path: String
    func helperExecutableURL() -> URL { URL(fileURLWithPath: path) }
}

private actor NoopExecutor: LaunchControlExecuting {
    func bootstrap(plistURL _: URL) async throws {}
    func bootout(label _: String) async throws {}
}

private extension LaunchAgentInstaller.PlistConfig {
    static func makeFor(label: String, executablePath: String) -> LaunchAgentInstaller.PlistConfig {
        LaunchAgentInstaller.PlistConfig(label: label, executablePath: executablePath)
    }
}

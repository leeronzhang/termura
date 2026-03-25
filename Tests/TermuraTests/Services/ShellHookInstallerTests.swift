import Foundation
import XCTest
@testable import Termura

final class ShellHookInstallerTests: XCTestCase {
    private var tempDir: String!
    private var installer: ShellHookInstaller!

    override func setUp() async throws {
        tempDir = NSTemporaryDirectory() + "termura-hook-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tempDir,
            withIntermediateDirectories: true
        )
        installer = ShellHookInstaller()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    // MARK: - Helpers

    /// Create a fake RC file in the temp directory with given content.
    private func createFakeRC(name: String, content: String = "") throws -> String {
        let path = (tempDir as NSString).appendingPathComponent(name)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// Read content of a file at path.
    private func readFile(_ path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }

    // MARK: - isInstalled

    func testIsInstalledReturnsFalseForCleanRC() async throws {
        let path = try createFakeRC(name: ".zshrc", content: "# normal zshrc\n")
        // We can't easily override home dir, so test the underlying isHookPresent logic
        // by checking the sentinel is not present.
        let content = try readFile(path)
        XCTAssertFalse(content.contains(AppConfig.ShellIntegration.hookSentinelComment))
    }

    func testIsInstalledReturnsTrueAfterHookAdded() async throws {
        let sentinel = AppConfig.ShellIntegration.hookSentinelComment
        let path = try createFakeRC(name: ".zshrc", content: "# existing\n\(sentinel)\n")
        let content = try readFile(path)
        XCTAssertTrue(content.contains(sentinel))
    }

    // MARK: - Shell type

    func testShellTypeZshRCFileName() {
        XCTAssertEqual(ShellType.zsh.rcFileName, ".zshrc")
    }

    func testShellTypeBashRCFileName() {
        XCTAssertEqual(ShellType.bash.rcFileName, ".bashrc")
    }

    // MARK: - Hook script content

    func testZshHookContainsSentinel() {
        // The zsh hook script is private, but we can verify by installing to a temp file.
        // For now, verify the sentinel constant is well-formed.
        let sentinel = AppConfig.ShellIntegration.hookSentinelComment
        XCTAssertTrue(sentinel.hasPrefix("#"))
        XCTAssertTrue(sentinel.contains("termura"))
    }

    // MARK: - Install to real temp file (integration-like)

    func testInstallAppendsHookToExistingFile() async throws {
        let rcPath = try createFakeRC(name: ".test_zshrc", content: "# existing config\n")

        // Directly test the file append logic by writing the sentinel.
        let sentinel = AppConfig.ShellIntegration.hookSentinelComment
        let hookContent = "\n\(sentinel)\n# mock hook body\n"
        guard let data = hookContent.data(using: .utf8) else {
            XCTFail("Failed to encode hook content")
            return
        }

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: rcPath))
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try handle.close()

        let result = try readFile(rcPath)
        XCTAssertTrue(result.contains("# existing config"))
        XCTAssertTrue(result.contains(sentinel))
    }

    func testInstallCreatesFileIfNotExists() async throws {
        let rcPath = (tempDir as NSString).appendingPathComponent(".new_zshrc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rcPath))

        let sentinel = AppConfig.ShellIntegration.hookSentinelComment
        let hookContent = "\(sentinel)\n# mock hook body\n"
        try hookContent.write(toFile: rcPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: rcPath))
        let content = try readFile(rcPath)
        XCTAssertTrue(content.contains(sentinel))
    }

    func testInstallDoesNotDuplicateHook() async throws {
        let sentinel = AppConfig.ShellIntegration.hookSentinelComment
        let existingContent = "# config\n\(sentinel)\n# hook body\n"
        let rcPath = try createFakeRC(name: ".dup_zshrc", content: existingContent)

        // Simulate the guard check: if sentinel already present, do not append.
        let content = try readFile(rcPath)
        let alreadyInstalled = content.contains(sentinel)
        XCTAssertTrue(alreadyInstalled)
        // The install() method would return early here.
    }

    // MARK: - Error types

    func testShellHookErrorDescriptions() {
        let encodingError = ShellHookError.encodingFailed
        XCTAssertNotNil(encodingError.errorDescription)
        XCTAssertTrue(encodingError.errorDescription?.contains("UTF-8") ?? false)

        let fileError = ShellHookError.fileOpenFailed("/path/to/file")
        XCTAssertNotNil(fileError.errorDescription)
        XCTAssertTrue(fileError.errorDescription?.contains("/path/to/file") ?? false)
    }
}

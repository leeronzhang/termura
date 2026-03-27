import Foundation
import XCTest
@testable import Termura

/// Tests for GitService timeout behavior, process error handling,
/// and non-git directory fallback.
///
/// Tests that need a real git repo create a temporary directory and
/// run `git init` to be environment-independent.
final class GitServiceTimeoutTests: XCTestCase {
    private let service = GitService()

    /// Creates a temporary git repo with a single committed file.
    private func makeTempGitRepo() throws -> String {
        let tmpDir = NSTemporaryDirectory() + "termura-git-test-\(UUID().uuidString)"
        let fm = FileManager.default
        try fm.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)

        let runGit = { (args: [String]) throws in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            proc.arguments = args
            proc.currentDirectoryURL = URL(fileURLWithPath: tmpDir)
            proc.environment = [
                "GIT_AUTHOR_NAME": "Test",
                "GIT_AUTHOR_EMAIL": "test@test.com",
                "GIT_COMMITTER_NAME": "Test",
                "GIT_COMMITTER_EMAIL": "test@test.com",
                "HOME": NSTemporaryDirectory()
            ]
            try proc.run()
            proc.waitUntilExit()
        }

        try runGit(["init"])
        let filePath = tmpDir + "/test.txt"
        try "hello".write(toFile: filePath, atomically: true, encoding: .utf8)
        try runGit(["add", "test.txt"])
        try runGit(["-c", "user.name=Test", "-c", "user.email=test@test.com", "commit", "-m", "init"])

        return tmpDir
    }

    private func removeTempDir(_ path: String) {
        do { try FileManager.default.removeItem(atPath: path) } catch { _ = error }
    }

    // MARK: - Non-git directory fallback

    func testStatusAtNonGitDirectoryReturnsNotARepo() async throws {
        let tmpDir = NSTemporaryDirectory() + "termura-git-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir,
            withIntermediateDirectories: true
        )
        defer { removeTempDir(tmpDir) }

        let result = try await service.status(at: tmpDir)
        XCTAssertFalse(result.isGitRepo)
    }

    // MARK: - Git status on real repo

    func testStatusAtGitRepoReturnsValidResult() async throws {
        let tmpDir = try makeTempGitRepo()
        defer { removeTempDir(tmpDir) }

        let result = try await service.status(at: tmpDir)
        XCTAssertTrue(result.isGitRepo)
    }

    // MARK: - Diff on non-existent file

    func testDiffOnNonexistentFileReturnsEmpty() async throws {
        let tmpDir = try makeTempGitRepo()
        defer { removeTempDir(tmpDir) }

        let result = try await service.diff(
            file: "this-file-does-not-exist-at-all.xyz",
            staged: false,
            at: tmpDir
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Tracked files

    func testTrackedFilesReturnsNonEmpty() async throws {
        let tmpDir = try makeTempGitRepo()
        defer { removeTempDir(tmpDir) }

        let files = try await service.trackedFiles(at: tmpDir)
        XCTAssertFalse(files.isEmpty)
        XCTAssertTrue(files.contains("test.txt"))
    }

    func testTrackedFilesOnNonGitDirThrows() async throws {
        let tmpDir = NSTemporaryDirectory() + "termura-git-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(
            atPath: tmpDir,
            withIntermediateDirectories: true
        )
        defer { removeTempDir(tmpDir) }

        do {
            _ = try await service.trackedFiles(at: tmpDir)
            XCTFail("Expected error for non-git directory")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - showFile

    func testShowFileReadsExistingFile() async throws {
        let tmpDir = try makeTempGitRepo()
        defer { removeTempDir(tmpDir) }

        let content = try await service.showFile(at: "test.txt", directory: tmpDir)
        XCTAssertEqual(content, "hello")
    }

    func testShowFileThrowsForMissingFile() async throws {
        let tmpDir = try makeTempGitRepo()
        defer { removeTempDir(tmpDir) }

        do {
            _ = try await service.showFile(at: "nonexistent.xyz", directory: tmpDir)
            XCTFail("Expected error for missing file")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - Timeout validation (config check)

    func testTimeoutConfigIsReasonable() {
        let timeoutNs = AppConfig.Git.commandTimeoutNanoseconds
        XCTAssertGreaterThanOrEqual(timeoutNs, 1_000_000_000)
        XCTAssertLessThanOrEqual(timeoutNs, 30_000_000_000)
    }

    // MARK: - Error type validation

    func testGitServiceErrorHasDescription() {
        let error = GitServiceError.commandFailed(
            command: "status",
            exitCode: 128,
            stderr: "fatal: not a git repository"
        )
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("128") ?? false)
    }

    func testGitServiceLaunchFailedErrorHasDescription() {
        let underlying = NSError(domain: "test", code: 1, userInfo: nil)
        let error = GitServiceError.launchFailed(
            command: "status",
            underlying: underlying
        )
        XCTAssertNotNil(error.errorDescription)
    }
}

import Foundation
@testable import Termura
import XCTest

@MainActor
final class AICommitServiceTests: XCTestCase {
    func testHeadlessUnsupportedAgentReturnsAgentUnsupported() async {
        let service = makeService(runner: MockRunner())
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .aider, fromSessionLabel: nil
        )
        XCTAssertEqual(result, .failure(
            reason: .agentUnsupported,
            message: "Aider headless mode not supported"
        ))
    }

    func testTimeoutMapsToTimedOutReason() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(exitCode: -1, stdout: "", stderr: "", timedOut: true)
        let service = makeService(runner: runner)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, _) = result else {
            return XCTFail("Expected failure on timeout")
        }
        XCTAssertEqual(reason, .timedOut)
    }

    func testAuthFailureMapsToAuthRequired() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 1,
            stdout: "",
            stderr: "Please log in to continue",
            timedOut: false
        )
        let service = makeService(runner: runner)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, message) = result else {
            return XCTFail("Expected auth failure")
        }
        XCTAssertEqual(reason, .authRequired)
        XCTAssertTrue(message.contains("login"))
    }

    func testBinaryMissingMapsToAgentNotFound() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 127, stdout: "", stderr: "command not found: claude", timedOut: false
        )
        let service = makeService(runner: runner)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, _) = result else {
            return XCTFail("Expected agentNotFound failure")
        }
        XCTAssertEqual(reason, .agentNotFound)
    }

    func testLaunchFailedMapsToAgentNotFound() async {
        let runner = MockRunner()
        runner.shouldThrowLaunchFailed = true
        let service = makeService(runner: runner)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, _) = result else {
            return XCTFail("Expected agentNotFound on launch failure")
        }
        XCTAssertEqual(reason, .agentNotFound)
    }

    func testAgentDeclinedWhenStatusStillDirty() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0, stdout: "(no commit was made)", stderr: "", timedOut: false
        )
        let git = MockGitService()
        await git.setStubbed(.init(
            branch: "main",
            files: [GitFileStatus(path: "Foo.swift", kind: .modified, isStaged: false)],
            isGitRepo: true, ahead: 0, behind: 0
        ))
        let service = makeService(runner: runner, git: git)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, _) = result else {
            return XCTFail("Expected agentDeclined")
        }
        XCTAssertEqual(reason, .agentDeclined)
    }

    func testHappyPathReturnsSuccessWithSubject() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0,
            stdout: "[main 1a2b3c4] feat: add commit popover",
            stderr: "",
            timedOut: false
        )
        let git = MockGitService()
        await git.setStubbed(.init(
            branch: "main", files: [], isGitRepo: true, ahead: 0, behind: 0
        ))
        let service = makeService(runner: runner, git: git)
        let result = await service.commit(
            note: "test note", projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: "main"
        )
        guard case let .success(subject) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(subject, "feat: add commit popover")
    }

    func testPromptEmbedsUserNote() {
        let prompt = AICommitPrompts.commit(note: "skip vendor/")
        XCTAssertTrue(prompt.contains("User context:"))
        XCTAssertTrue(prompt.contains("skip vendor/"))
    }

    func testPromptOmitsContextSectionWhenNoteEmpty() {
        let promptNil = AICommitPrompts.commit(note: nil)
        let promptBlank = AICommitPrompts.commit(note: "   \n\t")
        XCTAssertFalse(promptNil.contains("User context"))
        XCTAssertFalse(promptBlank.contains("User context"))
    }

    // MARK: - Remote setup

    func testSetupRemoteHappyPathReturnsSuccess() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0,
            stdout: "origin\thttps://github.com/user/repo (fetch)",
            stderr: "",
            timedOut: false
        )
        let service = makeService(runner: runner)
        let result = await service.setupRemote(
            note: "github user/repo",
            projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .success(summary) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(summary, "Remote configured")
    }

    func testSetupRemoteSkipsCommitWorkingTreeCheck() async {
        // setupRemote uses the same auth pattern detection. This verifies a clean exit
        // with no auth keywords + dirty status does NOT mark agentDeclined for remote setup.
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        let git = MockGitService()
        await git.setStubbed(.init(
            branch: "main",
            files: [GitFileStatus(path: "Foo.swift", kind: .modified, isStaged: false)],
            isGitRepo: true, ahead: 0, behind: 0
        ))
        let service = makeService(runner: runner, git: git)
        let result = await service.setupRemote(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case .success = result else {
            return XCTFail("Expected success — remote setup must not check working tree")
        }
    }

    func testSetupRemotePromptIncludesUserNote() {
        let prompt = AICommitPrompts.remoteSetup(note: "github user/repo")
        XCTAssertTrue(prompt.contains("github user/repo"))
        XCTAssertTrue(prompt.contains("git remote -v"))
    }

    func testSetupRemotePromptHasFallbackWhenNoteEmpty() {
        let prompt = AICommitPrompts.remoteSetup(note: nil)
        XCTAssertTrue(prompt.contains("sensible remote"))
    }

    // MARK: - Helpers

    private func makeService(
        runner: MockRunner = .init(),
        git: MockGitService = .init()
    ) -> AICommitService {
        AICommitService(
            runner: runner,
            shellEnv: StaticUserShellEnvironment(path: "/usr/bin:/bin"),
            gitService: git,
            timeout: .seconds(1)
        )
    }

    private func tmp() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
    }
}

// MARK: - Mock CLI runner

private final class MockRunner: CLIProcessRunnerProtocol, @unchecked Sendable {
    var stubbedOutput = CLIProcessOutput(exitCode: 0, stdout: "", stderr: "", timedOut: false)
    var shouldThrowLaunchFailed = false
    private(set) var lastInvocation: (executable: String, args: [String], cwd: URL)?

    func run(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String],
        timeout: Duration
    ) async throws -> CLIProcessOutput {
        lastInvocation = (executable, args, cwd)
        if shouldThrowLaunchFailed {
            throw CLIProcessRunnerError.launchFailed(
                executable: executable,
                underlying: NSError(domain: "test", code: 1)
            )
        }
        return stubbedOutput
    }
}

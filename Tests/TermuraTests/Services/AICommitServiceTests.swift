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

    /// Agent exits 0 but HEAD did not move → agentDeclined.
    /// Stubs the same SHA before and after to model "no commit happened".
    func testAgentDeclinedWhenHEADUnchanged() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0, stdout: "(no commit was made)", stderr: "", timedOut: false
        )
        let git = MockGitService()
        await git.setHeadSHADefault("abc1234")
        let service = makeService(runner: runner, git: git)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case let .failure(reason, _) = result else {
            return XCTFail("Expected agentDeclined")
        }
        XCTAssertEqual(reason, .agentDeclined)
    }

    /// Happy path: pre-SHA `abc1234`, post-SHA `def5678` (HEAD moved), commit
    /// subject read from git (NOT parsed from agent stdout).
    func testHappyPathReturnsSuccessWithSubject() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0,
            stdout: "anything the agent printed",
            stderr: "",
            timedOut: false
        )
        let git = MockGitService()
        await git.enqueueHeadSHAs(["abc1234", "def5678"])
        await git.setLastCommitSubject("feat: add commit popover")
        let service = makeService(runner: runner, git: git)
        let result = await service.commit(
            note: "test note", projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: "main"
        )
        guard case let .success(subject) = result else {
            return XCTFail("Expected success")
        }
        XCTAssertEqual(subject, "feat: add commit popover")
    }

    /// HEAD moved but git refused to surface a subject. Fallback string keeps the toast useful.
    func testHappyPathFallsBackToCommittedWhenSubjectMissing() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        let git = MockGitService()
        await git.enqueueHeadSHAs([nil, "first1234"]) // empty repo → first commit
        await git.setLastCommitSubject(nil)
        let service = makeService(runner: runner, git: git)
        let result = await service.commit(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        XCTAssertEqual(result, .success(summary: "Committed"))
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

    /// Locks in the natural-language-match instruction so a future prompt
    /// rewrite doesn't silently strip the Chinese-repo fix.
    func testPromptInstructsMatchingCommitSubjectLanguage() {
        let prompt = AICommitPrompts.commit(note: nil)
        XCTAssertTrue(prompt.contains("natural language"))
        XCTAssertTrue(prompt.contains("Chinese"))
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

    /// Verifies remote-setup uses the auth-pattern path but does NOT trigger
    /// the HEAD-delta check: a clean exit means "remote configured" regardless
    /// of working-tree state.
    func testSetupRemoteSkipsHEADCheck() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        let git = MockGitService()
        await git.setHeadSHADefault("abc1234") // would be "no commit" under commit path
        let service = makeService(runner: runner, git: git)
        let result = await service.setupRemote(
            note: nil, projectRoot: tmp(), agent: .claudeCode, fromSessionLabel: nil
        )
        guard case .success = result else {
            return XCTFail("Expected success — remote setup must not check HEAD")
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

    // MARK: - PATH probe caching

    func testProbeReturnsClaudeCodeWhenWhichSucceeds() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0, stdout: "/usr/local/bin/claude\n", stderr: "", timedOut: false
        )
        let service = makeService(runner: runner)
        let resolved = await service.probeAvailableHeadlessAgent()
        XCTAssertEqual(resolved, .claudeCode)
    }

    func testProbeCachesResultAcrossCalls() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 0, stdout: "/usr/local/bin/claude\n", stderr: "", timedOut: false
        )
        let service = makeService(runner: runner)
        _ = await service.probeAvailableHeadlessAgent()
        let probeCallsAfterFirst = runner.callCount
        _ = await service.probeAvailableHeadlessAgent()
        _ = await service.probeAvailableHeadlessAgent()
        XCTAssertEqual(runner.callCount, probeCallsAfterFirst,
                       "Second + third probe must use cache, not re-shell")
    }

    func testProbeCachesNegativeResult() async {
        let runner = MockRunner()
        runner.stubbedOutput = CLIProcessOutput(
            exitCode: 1, stdout: "", stderr: "", timedOut: false
        )
        let service = makeService(runner: runner)
        let first = await service.probeAvailableHeadlessAgent()
        XCTAssertNil(first)
        let countAfterFirst = runner.callCount
        _ = await service.probeAvailableHeadlessAgent()
        XCTAssertEqual(runner.callCount, countAfterFirst,
                       "Negative probe must also be cached so we don't re-shell on every popover")
    }

    // MARK: - Cancel

    /// `cancel()` is a no-op while idle and must not crash. Lifecycle invariant.
    func testCancelWhileIdleIsNoOp() async {
        let service = makeService(runner: MockRunner())
        service.cancel()
        XCTAssertFalse(service.isBusy)
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
    private(set) var callCount = 0

    func run(
        executable: String,
        args: [String],
        cwd: URL,
        env: [String: String],
        timeout: Duration
    ) async throws -> CLIProcessOutput {
        callCount += 1
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

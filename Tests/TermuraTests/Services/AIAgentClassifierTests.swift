import Foundation
@testable import Termura
import XCTest

/// Contract tests for the matcher patterns. These lock in the false-positive
/// regressions that motivated the stderr-only + exit-code-gated refactor:
///   - Agent stdout containing benign phrases like "sign in" or "pre-commit"
///     must not be reclassified as auth / hook failures on exit 0.
///   - Bare patterns ("please run", "auth required", "sign in") that used
///     to live in the auth list must no longer match — they collide too
///     often with explanatory prose in successful runs.
final class AIAgentClassifierTests: XCTestCase {
    // MARK: - matchesAuthFailure

    func testAuthFailureRequiresNonZeroExit() {
        XCTAssertFalse(AIAgentClassifier.matchesAuthFailure(
            stderr: "please log in", exitCode: 0
        ), "Exit 0 = the agent succeeded. Auth keywords in stderr noise must not trigger.")
    }

    func testAuthFailureMatchesPleaseLogIn() {
        XCTAssertTrue(AIAgentClassifier.matchesAuthFailure(
            stderr: "Please log in to continue", exitCode: 1
        ))
    }

    func testAuthFailureMatchesNotAuthenticated() {
        XCTAssertTrue(AIAgentClassifier.matchesAuthFailure(
            stderr: "Error: not authenticated", exitCode: 1
        ))
    }

    func testAuthFailureMatches401Unauthorized() {
        XCTAssertTrue(AIAgentClassifier.matchesAuthFailure(
            stderr: "HTTP 401 unauthorized", exitCode: 1
        ))
    }

    /// Regression: the old classifier matched the bare word "sign in" anywhere
    /// in combined stderr+stdout. A successful commit whose subject contained
    /// "Add sign in flow" got falsely flagged as auth-required.
    func testAuthFailureDoesNotMatchBareSignIn() {
        XCTAssertFalse(AIAgentClassifier.matchesAuthFailure(
            stderr: "Add sign in flow", exitCode: 1
        ), "Bare 'sign in' must NOT trigger — too generic, fires on legitimate commit subjects.")
    }

    /// Regression: the old classifier matched "please run". Agents say this
    /// all the time when suggesting next steps ("please run npm test").
    func testAuthFailureDoesNotMatchPleaseRun() {
        XCTAssertFalse(AIAgentClassifier.matchesAuthFailure(
            stderr: "Note: please run tests before pushing", exitCode: 1
        ))
    }

    // MARK: - matchesPreCommitHook

    func testPreCommitHookRequiresNonZeroExit() {
        XCTAssertFalse(AIAgentClassifier.matchesPreCommitHook(
            stderr: "pre-commit hook ran successfully", exitCode: 0
        ))
    }

    func testPreCommitHookMatchesExplicitHookFailure() {
        XCTAssertTrue(AIAgentClassifier.matchesPreCommitHook(
            stderr: "pre-commit hook failed: lint errors detected", exitCode: 1
        ))
    }

    func testPreCommitHookMatchesHuskyWithError() {
        XCTAssertTrue(AIAgentClassifier.matchesPreCommitHook(
            stderr: "husky - pre-commit hook exited with error", exitCode: 1
        ))
    }

    func testPreCommitHookMatchesLefthookWithError() {
        XCTAssertTrue(AIAgentClassifier.matchesPreCommitHook(
            stderr: "lefthook: error running pre-commit", exitCode: 1
        ))
    }

    /// Regression: old classifier matched the bare token "pre-commit" anywhere
    /// in combined stderr+stdout. Repos that mention pre-commit in their README
    /// or commit messages triggered false hook-failure toasts.
    func testPreCommitHookDoesNotMatchBareToken() {
        XCTAssertFalse(AIAgentClassifier.matchesPreCommitHook(
            stderr: "this repo uses pre-commit for formatting", exitCode: 1
        ), "Bare 'pre-commit' substring must NOT trigger — needs 'hook' / 'failed' context.")
    }

    func testPreCommitHookDoesNotMatchHuskyMention() {
        XCTAssertFalse(AIAgentClassifier.matchesPreCommitHook(
            stderr: "husky configuration detected", exitCode: 1
        ))
    }

    // MARK: - matchesBinaryMissing

    func testBinaryMissingMatchesExitCode127() {
        XCTAssertTrue(AIAgentClassifier.matchesBinaryMissing(
            stderr: "zsh: command not found: claude", exitCode: 127
        ))
    }

    func testBinaryMissingDoesNotMatchExit0() {
        XCTAssertFalse(AIAgentClassifier.matchesBinaryMissing(
            stderr: "command not found", exitCode: 0
        ))
    }

    // MARK: - shortErrorSnippet

    func testShortErrorSnippetPrefersStderr() {
        let output = CLIProcessOutput(
            exitCode: 1, stdout: "stdout-line", stderr: "stderr-line", timedOut: false
        )
        XCTAssertEqual(AIAgentClassifier.shortErrorSnippet(output: output), "stderr-line")
    }

    func testShortErrorSnippetFallsBackToStdoutWhenStderrEmpty() {
        let output = CLIProcessOutput(
            exitCode: 1, stdout: "stdout-line", stderr: "", timedOut: false
        )
        XCTAssertEqual(AIAgentClassifier.shortErrorSnippet(output: output), "stdout-line")
    }

    func testShortErrorSnippetTruncatesLongLines() {
        let long = String(repeating: "a", count: 200)
        let output = CLIProcessOutput(exitCode: 1, stdout: "", stderr: long, timedOut: false)
        let snippet = AIAgentClassifier.shortErrorSnippet(output: output)
        XCTAssertEqual(snippet.count, 121, "120 chars + '…'")
        XCTAssertTrue(snippet.hasSuffix("…"))
    }
}

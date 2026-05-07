import Foundation
@testable import Termura
import XCTest

/// Covers headless one-shot invocation: success / non-zero exit / launch failure / timeout.
final class CLIProcessRunnerTests: XCTestCase {
    private let runner = CLIProcessRunner()

    func testSuccessfulInvocationCapturesStdout() async throws {
        let result = try await runner.run(
            executable: "echo",
            args: ["hello"],
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            env: passthroughEnv,
            timeout: .seconds(5)
        )
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
        XCTAssertFalse(result.timedOut)
    }

    func testNonZeroExitIsReportedNotThrown() async throws {
        // `false` always exits 1 — verifies non-zero exit returns via output, not throws.
        let result = try await runner.run(
            executable: "false",
            args: [],
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            env: passthroughEnv,
            timeout: .seconds(5)
        )
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
    }

    func testMissingBinaryProducesNonZeroExit() async throws {
        // /usr/bin/env returns 127 when the requested executable is not found.
        let result = try await runner.run(
            executable: "termura-nonexistent-binary-zzz",
            args: [],
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            env: passthroughEnv,
            timeout: .seconds(5)
        )
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testTimeoutMarksOutputAsTimedOut() async throws {
        let result = try await runner.run(
            executable: "sleep",
            args: ["10"],
            cwd: URL(fileURLWithPath: NSTemporaryDirectory()),
            env: passthroughEnv,
            timeout: .milliseconds(200)
        )
        XCTAssertTrue(result.timedOut)
    }

    private var passthroughEnv: [String: String] {
        ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"]
    }
}

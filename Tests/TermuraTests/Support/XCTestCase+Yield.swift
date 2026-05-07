import Foundation
import XCTest

/// Yield for the given duration, allowing pending fire-and-forget Tasks
/// and debounced Combine pipelines to execute.
/// Uses ContinuousClock as the XCTest-idiomatic delay primitive.
func yieldForDuration(seconds: TimeInterval) async throws {
    try await ContinuousClock().sleep(for: .milliseconds(Int(seconds * 1000)))
}

/// Waits until `condition` becomes true, polling at a short interval.
/// Prefer this over fixed sleeps in async tests so assertions track state, not guessed timing.
@MainActor
func waitUntil(
    timeout seconds: TimeInterval = 1.0,
    pollingIntervalMillis: Int = 10,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @escaping () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await condition() { return }
        try await clock.sleep(for: .milliseconds(pollingIntervalMillis))
    }
    XCTFail("Condition not satisfied within \(seconds)s", file: file, line: line)
}

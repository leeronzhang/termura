import Foundation

/// Yield for the given duration, allowing pending fire-and-forget Tasks
/// and debounced Combine pipelines to execute.
/// Uses ContinuousClock as the XCTest-idiomatic delay primitive.
func yieldForDuration(seconds: TimeInterval) async throws {
    try await ContinuousClock().sleep(for: .milliseconds(Int(seconds * 1000)))
}

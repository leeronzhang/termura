import Foundation
@testable import Termura

/// No-op clock for deterministic tests -- sleeps return instantly, time is fixed.
/// Thread safety: only accessed from a single test actor; @unchecked is safe for test-only use.
final class TestClock: AppClock, @unchecked Sendable { // swiftlint:disable:this unchecked_sendable_documentation
    var sleepCallCount = 0
    /// Fixed date returned by `now()`. Defaults to reference date for deterministic tests.
    var currentDate: Date = .init(timeIntervalSinceReferenceDate: 0)

    func sleep(for duration: Duration) async throws {
        sleepCallCount += 1
    }

    func now() -> Date { currentDate }
}

// UserDefaults is thread-safe per Apple documentation; this test-only retroactive
// Sendable conformance is used to keep Swift 6 strict concurrency warnings quiet.
extension UserDefaults: @retroactive @unchecked Sendable {}

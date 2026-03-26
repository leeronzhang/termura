import Foundation
@testable import Termura

/// No-op clock for deterministic tests -- sleeps return instantly.
final class TestClock: AppClock, @unchecked Sendable {
    var sleepCallCount = 0
    func sleep(for duration: Duration) async throws {
        sleepCallCount += 1
    }
}

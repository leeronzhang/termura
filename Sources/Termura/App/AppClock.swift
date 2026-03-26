import Foundation

/// Abstraction over ContinuousClock for testable async sleeps.
/// See CLAUDE.md section 8: time-sensitive logic must inject Clock protocol.
protocol AppClock: Sendable {
    func sleep(for duration: Duration) async throws
}

/// Default production clock backed by ContinuousClock.
struct LiveClock: AppClock {
    private let clock = ContinuousClock()

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

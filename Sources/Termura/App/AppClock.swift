import Foundation

/// Abstraction over ContinuousClock for testable async sleeps and timestamps.
/// See CLAUDE.md section 8: time-sensitive logic must inject Clock protocol.
protocol AppClock: Sendable {
    func sleep(for duration: Duration) async throws
    /// Returns the current wall-clock time. Inject this instead of calling `Date()` directly.
    func now() -> Date
}

/// Default production clock backed by ContinuousClock.
struct LiveClock: AppClock {
    private let clock = ContinuousClock()

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }

    func now() -> Date { Date() }
}

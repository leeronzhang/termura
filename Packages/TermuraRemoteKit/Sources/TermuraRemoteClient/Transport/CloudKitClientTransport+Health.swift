// `Configuration` + `PollHealth` value types extracted from
// `CloudKitClientTransport.swift` so the parent file stays under
// SwiftLint's 300-line file_length warning threshold. Both types
// are public surface used by callers configuring the transport
// (RemoteStore / Settings UI) and reading its health snapshot;
// keeping them adjacent in their own file makes the contract
// reviewable without dragging the actor body into the diff.

import Foundation

public extension CloudKitClientTransport {
    struct Configuration: Sendable {
        public let pollInterval: Duration
        /// Maximum consecutive poll failures before the transport flags itself
        /// `.unhealthy`. Tuned to ~5 × 60s — long enough to ride out a Wi-Fi
        /// roam, short enough that a sustained CloudKit outage gets visible.
        public let healthFailureThreshold: Int
        /// Cap on the exponential backoff delay applied between poll
        /// attempts after consecutive failures.
        public let backoffCap: Duration
        /// D-3 — after this many consecutive failures we stop polling
        /// (`isCircuitOpen = true`) instead of plateauing at
        /// `backoffCap` forever. iOS-side recovery is via
        /// `disconnect()` + `connect()` (the next reconnect cycle
        /// instantiates a fresh transport with a clean breaker).
        public let circuitBreakerThreshold: Int

        public init(
            pollInterval: Duration = .seconds(60),
            healthFailureThreshold: Int = 5,
            backoffCap: Duration = .seconds(600),
            circuitBreakerThreshold: Int = 16
        ) {
            self.pollInterval = pollInterval
            self.healthFailureThreshold = healthFailureThreshold
            self.backoffCap = backoffCap
            self.circuitBreakerThreshold = circuitBreakerThreshold
        }
    }

    /// Poll-loop health summary. `unhealthy` flips on after
    /// `healthFailureThreshold` consecutive failures and clears the moment a
    /// poll succeeds; `isCircuitOpen` (D-3) flips after
    /// `circuitBreakerThreshold` failures and stays set until
    /// `disconnect()` resets the actor — at which point the polling
    /// loop has already exited so a stuck CloudKit outage stops draining
    /// battery + cellular data.
    struct PollHealth: Sendable, Equatable {
        public let isHealthy: Bool
        public let consecutiveFailures: Int
        public let lastFailureReason: String?
        public let isCircuitOpen: Bool

        public init(
            isHealthy: Bool,
            consecutiveFailures: Int,
            lastFailureReason: String? = nil,
            isCircuitOpen: Bool = false
        ) {
            self.isHealthy = isHealthy
            self.consecutiveFailures = consecutiveFailures
            self.lastFailureReason = lastFailureReason
            self.isCircuitOpen = isCircuitOpen
        }

        public static let healthy = PollHealth(isHealthy: true, consecutiveFailures: 0)
    }
}

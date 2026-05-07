// PR8 Phase 2 — keeps the single XPC connection to the LaunchAgent
// alive across the app's lifetime. `start()` resumes the underlying
// NSXPCConnection (via `RemoteAgentXPCClient`) and pings the agent
// once to demand-launch it through launchd. Connection invalidation
// triggers a backoff-delayed reconnect; a missing agent (e.g. the
// LaunchAgent plist hasn't been installed yet) is swallowed so app
// launch is never blocked.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteAgentAutoConnector")

@MainActor
final class RemoteAgentAutoConnector {
    /// Wave 1 — exponential-backoff schedule for invalidation-driven
    /// reconnect. The pre-Wave-1 implementation slept a fixed 1 s
    /// between attempts, so a misconfigured plist (mach-service typo,
    /// missing helper bundle, codesign mismatch) burned ~1 reconnect
    /// every second forever. We now stretch out the wait after each
    /// consecutive failure and stop driving the loop entirely once we
    /// hit the circuit-breaker cap; Settings UI surfaces the failure
    /// via `lastConnectError` so the user gets an actionable signal.
    static let backoffSchedule: [Duration] = [
        .seconds(1),
        .seconds(2),
        .seconds(4),
        .seconds(8),
        .seconds(16),
        .seconds(32),
        .seconds(60)
    ]

    /// After this many consecutive failed reconnect attempts we stop
    /// retrying automatically. The user has to hit the Settings toggle
    /// (or call `resumeAfterCircuitBreaker()`) to give the system
    /// another go — a typo in the plist won't get fixed by waking up
    /// once a minute and trying again.
    static let circuitBreakerThreshold = 8

    private let client: RemoteAgentXPCClient
    private var reconnectTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private(set) var isRunning = false
    private(set) var isCircuitOpen = false
    private(set) var lastConnectError: String?

    init(client: RemoteAgentXPCClient) {
        self.client = client
    }

    func start() async {
        guard !isRunning else { return }
        isRunning = true
        isCircuitOpen = false
        consecutiveFailures = 0
        await client.start()
        await pingBestEffort()
    }

    func stop() async {
        guard isRunning else { return }
        isRunning = false
        reconnectTask?.cancel()
        reconnectTask = nil
        consecutiveFailures = 0
        isCircuitOpen = false
        await client.stopAgent()
        await client.stop()
    }

    /// Wave 1 — Settings UI hook. Callable when `isCircuitOpen` is
    /// true to give the system another go after the user fixed the
    /// underlying plist / codesign issue. Resets the failure counter
    /// and kicks one reconnect attempt off the schedule's first slot.
    func resumeAfterCircuitBreaker() async {
        guard isRunning, isCircuitOpen else { return }
        isCircuitOpen = false
        consecutiveFailures = 0
        await client.start()
        await pingBestEffort()
    }

    /// Called by `RemoteAgentXPCClient.invalidationHandler` (off the
    /// main actor) when the connection drops. We hop back to the main
    /// actor, then schedule the next reconnect attempt at the
    /// exponential-backoff offset matching the consecutive-failure
    /// counter. Once the counter reaches `circuitBreakerThreshold`,
    /// we set `isCircuitOpen` and stop retrying.
    nonisolated func handleInvalidation() {
        Task { @MainActor in
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let attempt = consecutiveFailures
        if attempt >= Self.circuitBreakerThreshold {
            isCircuitOpen = true
            lastConnectError = "Agent reconnect failed \(attempt) times in a row; auto-retry paused. " +
                "Toggle remote control off and on after fixing the LaunchAgent setup."
            logger.warning(
                "AutoConnector circuit breaker opened after \(attempt) failures; manual resume required"
            )
            return
        }
        let delay = Self.backoffSchedule[min(attempt, Self.backoffSchedule.count - 1)]
        reconnectTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard isRunning, !isCircuitOpen else { return }
            await client.start()
            await pingBestEffort()
        }
    }

    private func pingBestEffort() async {
        do {
            try await client.pingAgent()
            consecutiveFailures = 0
            lastConnectError = nil
        } catch {
            consecutiveFailures += 1
            lastConnectError = error.localizedDescription
            let count = consecutiveFailures
            logger.info("agent ping failed (#\(count)): \(error.localizedDescription)")
        }
    }
}

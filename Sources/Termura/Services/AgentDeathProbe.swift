// PR9 v2.2 §9.3 / §9.3.3 — gates fallback B in `RemoteControlController.
// resetPairings()`. The safety of `AgentKeychainFallbackCleaner` comes
// from the 5s grace period plus a fresh probe returning `.confirmedDead`
// — an engineering-grade confirmation that the agent has exited its
// teardown window and no longer holds in-memory copies of cursor /
// quarantine state. It is NOT a sufficiency proof based on "XPC
// unreachable" alone. Any `.possiblyAlive` / `.indeterminate` result
// must route to γ (skip B, write a partial-error message) rather than
// silently corrupting the agent's persistent state.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentDeathProbe")

enum ProbeResult: Sendable, Equatable {
    case confirmedDead
    case possiblyAlive
    case indeterminate
}

protocol AgentDeathProbing: Sendable {
    func confirmUnreachable(machServiceName: String) async -> ProbeResult
}

struct AgentDeathProbe: AgentDeathProbing {
    private let clock: any AppClock
    private let gracePeriod: Duration
    private let probeTimeout: Duration
    private let probeOnce: @Sendable (String, Duration) async -> ProbeResult

    init(
        clock: any AppClock = LiveClock(),
        gracePeriod: Duration = .seconds(5),
        probeTimeout: Duration = .seconds(1),
        probeOnce: @escaping @Sendable (String, Duration) async -> ProbeResult = AgentDeathProbe.liveProbeOnce
    ) {
        self.clock = clock
        self.gracePeriod = gracePeriod
        self.probeTimeout = probeTimeout
        self.probeOnce = probeOnce
    }

    func confirmUnreachable(machServiceName: String) async -> ProbeResult {
        do {
            try await clock.sleep(for: gracePeriod)
        } catch {
            // Cancelled grace period collapses the probe to indeterminate
            // — we don't have ground truth about agent liveness.
            return .indeterminate
        }
        return await probeOnce(machServiceName, probeTimeout)
    }

    /// Live NSXPC-based probe-once. Opens a fresh `NSXPCConnection`
    /// for the named mach service, attempts a no-op ping through a
    /// probe-private protocol, and observes:
    ///   * invalidation handler fires (mach name unregistered)
    ///     → `.confirmedDead`
    ///   * proxy reply or error handler fires (mach name registered;
    ///     either agent honors the protocol or rejects it — both
    ///     mean agent is reachable)
    ///     → `.possiblyAlive`
    ///   * neither within timeout
    ///     → `.indeterminate`
    /// Untested by automated suites — exercising it requires a real
    /// `NSXPCListener` registered on a per-user mach name. The
    /// `probeOnce` injection point above lets every controller-level
    /// test substitute a deterministic implementation.
    static let liveProbeOnce: @Sendable (String, Duration) async -> ProbeResult = { machServiceName, timeout in
        await withCheckedContinuation { (cont: CheckedContinuation<ProbeResult, Never>) in
            let flag = ProbeOnceFlag()
            let conn = NSXPCConnection(machServiceName: machServiceName)
            conn.remoteObjectInterface = NSXPCInterface(with: AgentDeathPingProtocol.self)
            // Single resolution path used by every racing handler /
            // reply / timeout below; the actor's `tryFire()` ensures
            // `cont.resume(...)` runs at most once.
            let resolve: @Sendable (ProbeResult) -> Void = { value in
                Task {
                    if await flag.tryFire() {
                        cont.resume(returning: value)
                    }
                }
            }
            conn.invalidationHandler = { resolve(.confirmedDead) }
            conn.interruptionHandler = { resolve(.possiblyAlive) }
            conn.resume()
            // Force the bootstrap_look_up by retrieving and invoking
            // the proxy. Either the reply or the error handler will
            // arrive on a reachable agent; lookup failure is caught by
            // `invalidationHandler` above.
            let proxy = conn.remoteObjectProxyWithErrorHandler { _ in
                resolve(.possiblyAlive)
            } as? AgentDeathPingProtocol
            proxy?.deathProbePing { _ in resolve(.possiblyAlive) }
            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    // Cancellation just races the resolution paths
                    // above; the dedup flag still terminates `cont`.
                }
                resolve(.indeterminate)
                conn.invalidate()
            }
        }
    }
}

/// Probe-private NSXPC interface. Declared locally on purpose: the
/// agent's real bridge protocol lives in a private clang module that
/// public-repo code is forbidden to import (open-core boundary §12).
/// The agent will reject any method this probe-only protocol declares
/// — that rejection is precisely the "agent reachable" signal we want.
@objc private protocol AgentDeathPingProtocol {
    func deathProbePing(reply: @escaping @Sendable (Bool) -> Void)
}

/// Dedup actor used by the live NSXPC probe to ensure the
/// `CheckedContinuation` resumes exactly once across the four racing
/// resolution paths (invalidation handler / interruption handler /
/// proxy reply / proxy error / timeout). Each handler hops onto this
/// actor via a `Task`; `tryFire()` returns `true` only for the first
/// caller, so subsequent races fall on the floor.
private actor ProbeOnceFlag {
    private var fired = false
    func tryFire() -> Bool {
        guard !fired else { return false }
        fired = true
        return true
    }
}

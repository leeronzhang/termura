// PR8 Phase 2 — process-level orchestrator for the LaunchAgent.
// Owns: XPC service, CloudKit runner, dispatcher, cursor / quarantine
// stores, heartbeat. Resolves the local cloudSourceDeviceId by
// reading the shared keychain DeviceIdentity (the main app puts it
// there during PR1; the agent reads-only).
//
// Stop semantics (§6.1): each subsystem teardown is wrapped in a
// 4-second timeout so SIGTERM → exit(0) completes within ≤5s.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentLifecycle")

@MainActor
final class AgentLifecycle {
    private let gateway: any CloudKitDatabaseGateway
    private let pollInterval: Duration
    private let identityStore: KeychainDeviceIdentityStore

    private var xpcService: AgentXPCService?
    private var runner: AgentCloudKitRunner?
    private var dispatcher: AgentAppDispatcher?
    private var heartbeat: AgentHeartbeat?
    // Renamed from `pushDelegate` to satisfy SwiftLint's
    // `weak_delegate` rule which assumes any property suffixed with
    // `Delegate` should be weak. This holder owns the silent-push
    // adapter strongly because there is no other retainer in this
    // process; weakening would let it be released immediately.
    private var pushAdapter: AgentPushDelegate?
    // PR9 — held here so `resetState()` can address them. They were
    // already constructed in `wireSubsystems` and passed to the runner
    // and dispatcher; lifecycle now also retains a reference so the
    // resetPairings flow can wipe both stores via the XPC bridge.
    private var cursorStore: AgentCursorStore?
    private var quarantineStore: AgentQuarantineStore?

    private var stopContinuation: CheckedContinuation<Void, Never>?
    private var hasStopped = false

    init(
        gateway: any CloudKitDatabaseGateway,
        identityStore: KeychainDeviceIdentityStore = KeychainDeviceIdentityStore(
            serviceName: "com.termura.remote.identity"
        ),
        // Pre-fix the agent polled CloudKit every 60 s by default,
        // matching the public package's `CloudKitTransport.Configuration`
        // default. The Mac harness already overrides its in-app
        // CloudKitTransport to 5 s (see `RemoteServerHarness+Migration.
        // macCloudKitTransportConfiguration()`) for the same reason
        // documented there: 60 s makes interactive cross-network
        // pair / rejoin take 60-120 s in the field, and the agent
        // is plugged in / on AC so the battery argument doesn't
        // apply. CK free tier is 40 req/s; 0.2 req/s here is three
        // orders of magnitude under the limit.
        pollInterval: Duration = .seconds(5)
    ) {
        self.gateway = gateway
        self.identityStore = identityStore
        self.pollInterval = pollInterval
    }

    /// Static factory used by `main.swift` so the live-CloudKit
    /// gateway construction (which traps on missing entitlement) is
    /// gated to the production path. Tests inject a fake gateway via
    /// the designated initialiser.
    static func makeLive() -> AgentLifecycle {
        AgentLifecycle(gateway: LiveCloudKitDatabaseGateway())
    }

    func run() async {
        guard !hasStopped else { return }
        installSignalHandlers()
        do {
            try await wireSubsystems()
        } catch {
            logger.error("wiring failed; agent will idle: \(error.localizedDescription)")
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.stopContinuation = cont
        }
        await teardown()
    }

    func requestStop() {
        guard !hasStopped else { return }
        hasStopped = true
        stopContinuation?.resume(returning: ())
        stopContinuation = nil
    }

    private func wireSubsystems() async throws {
        let identity = try await identityStore.loadOrCreate()
        let macDeviceId = DeviceIdentity.deriveDeviceId(from: identity.publicKeyData)
        let cursor = AgentCursorStore()
        let quarantine = AgentQuarantineStore()
        let dispatcher = AgentAppDispatcher(
            cursorStore: cursor,
            quarantineStore: quarantine,
            gateway: gateway
        )
        let runner = AgentCloudKitRunner(
            macDeviceId: macDeviceId,
            gateway: gateway,
            cursorStore: cursor,
            quarantineStore: quarantine,
            dispatcher: dispatcher,
            pollInterval: pollInterval
        )
        let onPing: @Sendable () -> Void = { [weak runner] in
            guard let runner else { return }
            Task { await runner.pollOnce() }
        }
        let onStop: @Sendable () -> Void = { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.requestStop() }
        }
        // PR9 — bridges the XPC `resetAgentState` RPC to the lifecycle's
        // own `resetState()`. The reply is delayed inside the bridge
        // until this closure returns, so the main app's controller
        // observes a real ack before advancing to β-probe.
        let onReset: @Sendable () async -> Void = { [weak self] in
            await self?.resetState()
        }
        let bridge = AgentBridgeXPCBridge(onPing: onPing, onStop: onStop, onReset: onReset)
        let xpcDispatcher = dispatcher
        let onConnection: @Sendable (ConnectionHolder?) -> Void = { holder in
            Task { await xpcDispatcher.bind(connection: holder) }
        }
        let xpc = AgentXPCService(bridge: bridge, onConnectionAvailable: onConnection)
        let push = AgentPushDelegate(runner: runner)
        let heartbeat = AgentHeartbeat()
        self.dispatcher = dispatcher
        self.runner = runner
        xpcService = xpc
        pushAdapter = push
        self.heartbeat = heartbeat
        cursorStore = cursor
        quarantineStore = quarantine
        xpc.start()
        Task {
            await runner.start()
            await heartbeat.start()
        }
    }

    private func teardown() async {
        if let runner {
            await withTimeoutSeconds(4) { await runner.stop() }
        }
        if let dispatcher {
            await withTimeoutSeconds(4) { await dispatcher.stop() }
        }
        if let xpcService {
            xpcService.stop()
        }
        if let heartbeat {
            await heartbeat.cancel()
        }
        runner = nil
        dispatcher = nil
        xpcService = nil
        heartbeat = nil
        pushAdapter = nil
        cursorStore = nil
        quarantineStore = nil
    }

    /// PR9 — wipes the agent's persistent decision state (cursor +
    /// quarantine) so a re-enable of remote control after a
    /// `resetPairings` starts from epoch zero with no quarantined
    /// records. Best-effort: per-store failures are logged but do
    /// not throw — the main app's β-probe + γ-fallback in
    /// `RemoteControlController.resetPairings` is the authoritative
    /// safety net (see PR9 v2.2 §9.4 / §12.6.1). Callable while the
    /// agent is wired (post-`wireSubsystems`); a no-op pre-wire and
    /// post-`teardown`.
    func resetState() async {
        if let cursorStore {
            do {
                try await cursorStore.reset()
            } catch {
                logger.warning("cursor reset failed: \(error.localizedDescription)")
            }
        }
        if let quarantineStore {
            do {
                try await quarantineStore.removeAll()
            } catch {
                logger.warning("quarantine removeAll failed: \(error.localizedDescription)")
            }
        }
    }

    private func withTimeoutSeconds(
        _ seconds: TimeInterval,
        _ work: @Sendable @escaping () async -> Void
    ) async {
        let task = Task { await work() }
        let timer = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
                task.cancel()
            } catch {
                // CancellationError is expected — the work task
                // finished and we're racing to cancel the timer.
                return
            }
        }
        await task.value
        timer.cancel()
    }

    private func installSignalHandlers() {
        let stopHandler: @convention(c) (Int32) -> Void = { _ in
            Task { @MainActor in
                AgentLifecycle.shared?.requestStop()
            }
        }
        signal(SIGTERM, stopHandler)
        signal(SIGINT, stopHandler)
    }

    nonisolated(unsafe) static var shared: AgentLifecycle?
}

// PR8 Phase 2 — private-repo concrete impl of the public-repo
// `RemoteAgentBridgeLifecycle` protocol. Owns the agent-side glue
// (XPC client + ingress + auto-connector) and lazy-builds them on
// first `start()` so app-launch path can stay synchronous. The
// open-core repo only sees this through `any
// RemoteAgentBridgeLifecycle`; concrete type is wired by
// `RemoteIntegrationFactory.makeAgentBridge`.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteAgentBridgeAssembly")

enum RemoteAgentBridgeAssemblyError: Error, Sendable, Equatable {
    /// PR9 — `resetAgentState()` was invoked before `start()` (or after
    /// `stop()`). The caller must `start()` the bridge first so the
    /// XPC client is wired and launchd can demand-launch the agent.
    case bridgeNotStarted
}

extension RemoteAgentBridgeAssemblyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .bridgeNotStarted:
            "Remote agent bridge isn't running. Start it before invoking this operation."
        }
    }
}

actor RemoteAgentBridgeAssembly: RemoteAgentBridgeLifecycle {
    private let harness: RemoteServerHarness
    private var ingress: AgentInjectedCloudKitIngress?
    private var autoConnector: RemoteAgentAutoConnector?
    private var bridge: AppMailboxXPCBridge?
    private var client: RemoteAgentXPCClient?
    private var isStarted = false

    init(harness: RemoteServerHarness) {
        self.harness = harness
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        do {
            try await wire()
        } catch {
            logger.warning("agent bridge wiring failed; remote-control via agent unavailable: \(error.localizedDescription)")
            isStarted = false
            return
        }
        if let connector = autoConnector {
            Task { @MainActor in
                await connector.start()
            }
        }
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        if let connector = autoConnector {
            Task { @MainActor in
                await connector.stop()
            }
        }
        await ingress?.shutdown()
        ingress = nil
        bridge = nil
        client = nil
        autoConnector = nil
    }

    /// PR9 — proxies the public `RemoteAgentBridgeLifecycle` RPC down to
    /// the held `RemoteAgentXPCClient`. Errors from the client (proxy
    /// failure, connection invalidation, agent unavailable) propagate
    /// so the controller's β-probe + γ-fallback path can decide whether
    /// to escalate to keychain B-fallback. Pre-`start()` invocation is
    /// a configuration error: throw `bridgeNotStarted` rather than
    /// silently no-op'ing — the caller (`RemoteControlController.
    /// resetPairings`) is responsible for ordering `start()` first.
    func resetAgentState() async throws {
        guard isStarted, let client else {
            throw RemoteAgentBridgeAssemblyError.bridgeNotStarted
        }
        try await client.resetAgentState()
    }

    private func wire() async throws {
        let stack = try await harness.ensureAssembled()
        let gate = TrustedSourceGate(store: stack.pairedDeviceStore)
        let ingress = AgentInjectedCloudKitIngress(
            router: stack.router,
            gate: gate,
            pairKeyStore: stack.pairKeyStore,
            gateway: stack.gateway,
            macDeviceId: stack.macDeviceId,
            codec: stack.codec
        )
        self.ingress = ingress
        let bridgeProvider: @Sendable () async -> AgentInjectedCloudKitIngress? = { [weak self] in
            await self?.ingress
        }
        let bridge = AppMailboxXPCBridge(ingressProvider: bridgeProvider)
        self.bridge = bridge
        let client = RemoteAgentXPCClient(bridge: bridge)
        self.client = client
        let connector = await MainActor.run { RemoteAgentAutoConnector(client: client) }
        autoConnector = connector
    }
}

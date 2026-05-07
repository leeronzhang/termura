// PR8 Phase 2 — main app's single NSXPCConnection to the LaunchAgent.
// Owns: outgoing connection to `com.termura.remote-agent`. Configures
// the connection's `remoteObjectInterface = AgentBridgeProtocol` and
// `exportedInterface = AppMailboxProtocol` + `exportedObject =
// AppMailboxXPCBridge`, so a single connection carries both
// directions of RPC. Resume on `start`, invalidate on `stop`. The
// invalidation handler triggers `RemoteAgentAutoConnector` to
// reconnect; a missing agent (mach service unregistered) results in
// a swallowed error so app launch never blocks on it.

import Foundation
import OSLog
import TermuraAgentXPCInterfaces

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteAgentXPCClient")

actor RemoteAgentXPCClient {
    enum ClientError: Error, Sendable, Equatable, LocalizedError {
        case notRunning
        case agentUnavailable

        var errorDescription: String? {
            switch self {
            case .notRunning:
                "Remote agent XPC client is not running."
            case .agentUnavailable:
                "Remote agent is not reachable. The LaunchAgent may be missing or refusing to launch."
            }
        }
    }

    static let machServiceName = "com.termura.remote-agent"

    private let bridge: AppMailboxXPCBridge
    private var connection: NSXPCConnection?
    private let onInvalidate: @Sendable () async -> Void
    private var isStopped = false

    init(
        bridge: AppMailboxXPCBridge,
        onInvalidate: @escaping @Sendable () async -> Void = {}
    ) {
        self.bridge = bridge
        self.onInvalidate = onInvalidate
    }

    func start() {
        guard connection == nil, !isStopped else { return }
        let conn = NSXPCConnection(machServiceName: Self.machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: AgentBridgeProtocol.self)
        conn.exportedInterface = NSXPCInterface(with: AppMailboxProtocol.self)
        conn.exportedObject = bridge
        let invalidate = onInvalidate
        conn.invalidationHandler = {
            Task { await invalidate() }
        }
        conn.interruptionHandler = {
            logger.info("RemoteAgentXPCClient connection interrupted")
        }
        conn.resume()
        connection = conn
    }

    func stop() async {
        isStopped = true
        connection?.invalidate()
        connection = nil
    }

    /// Best-effort ping; treats any XPC error (including agent
    /// unavailable) as `agentUnavailable` so the auto-connector can
    /// surface it without crashing app launch.
    func pingAgent() async throws {
        guard let connection else { throw ClientError.notRunning }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                logger.info("pingAgent proxy error: \(error.localizedDescription)")
                cont.resume(throwing: ClientError.agentUnavailable)
            } as? AgentBridgeProtocol
            guard let proxy else {
                cont.resume(throwing: ClientError.agentUnavailable)
                return
            }
            proxy.pingAgent(reply: { _ in
                cont.resume(returning: ())
            })
        }
    }

    func stopAgent() async {
        guard let connection else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { _ in
                cont.resume()
            } as? AgentBridgeProtocol
            guard let proxy else {
                cont.resume()
                return
            }
            proxy.stopAgent(reply: { _ in
                cont.resume()
            })
        }
    }

    /// PR9 — fires the `resetAgentState` RPC and waits for the agent's
    /// ack. Unlike `stopAgent`, errors propagate so the caller's
    /// β-probe + γ-fallback flow keys off a real signal: connection
    /// invalidation or proxy errors surface as `agentUnavailable`.
    func resetAgentState() async throws {
        guard let connection else { throw ClientError.notRunning }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                logger.info("resetAgentState proxy error: \(error.localizedDescription)")
                cont.resume(throwing: ClientError.agentUnavailable)
            } as? AgentBridgeProtocol
            guard let proxy else {
                cont.resume(throwing: ClientError.agentUnavailable)
                return
            }
            proxy.resetAgentState(reply: { _ in
                cont.resume(returning: ())
            })
        }
    }
}

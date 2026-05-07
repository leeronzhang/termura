// PR8 Phase 2 — owns the single `com.termura.remote-agent` mach
// service NSXPCListener. Configures each accepted connection with
// `exportedInterface = AgentBridgeProtocol`, `exportedObject =
// AgentBridgeXPCBridge`, and `remoteObjectInterface =
// AppMailboxProtocol` so the same connection carries forward and
// reverse RPC. Pushes the inbound proxy to the dispatcher via
// `ConnectionHolder`, so agent → app deliveries reuse the same
// connection the app opened.

import Foundation
import OSLog
@preconcurrency import TermuraAgentXPCInterfaces

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentXPCService")

// `@unchecked Sendable` (CLAUDE.md §4.5 #1): NSXPCListenerDelegate is `@objc`
// so the implementing type must be an NSObject subclass; NSObject is not
// Sendable. Thread safety: `bridge` and `onConnectionAvailable` are immutable
// `let` Sendable values; `listener` is mutated only on the main path
// (start/stop) and during NSXPC accept callbacks; `activeConnections` is
// guarded by `activeConnectionsLock` for every read and write.
final class AgentXPCService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    static let machServiceName = "com.termura.remote-agent"

    private let bridge: AgentBridgeXPCBridge
    private let onConnectionAvailable: @Sendable (ConnectionHolder?) -> Void
    private var listener: NSXPCListener?
    private let activeConnectionsLock = NSLock()
    private var activeConnections: [NSXPCConnection] = []

    init(
        bridge: AgentBridgeXPCBridge,
        onConnectionAvailable: @escaping @Sendable (ConnectionHolder?) -> Void
    ) {
        self.bridge = bridge
        self.onConnectionAvailable = onConnectionAvailable
    }

    func start() {
        guard listener == nil else { return }
        let listener = NSXPCListener(machServiceName: Self.machServiceName)
        listener.delegate = self
        listener.resume()
        self.listener = listener
        logger.info("XPC listener resumed on \(Self.machServiceName, privacy: .public)")
    }

    func stop() {
        listener?.invalidate()
        listener = nil
        let conns: [NSXPCConnection]
        activeConnectionsLock.lock()
        conns = activeConnections
        activeConnections.removeAll()
        activeConnectionsLock.unlock()
        for conn in conns {
            conn.invalidate()
        }
        onConnectionAvailable(nil)
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // `auditToken` validation could go here in a future PR (verify
        // same uid/team). For PR8 Phase 2 we accept any local
        // connection so the main app's NSXPCConnection always lands.
        newConnection.exportedInterface = NSXPCInterface(with: (any AgentBridgeProtocol).self)
        newConnection.exportedObject = bridge
        newConnection.remoteObjectInterface = NSXPCInterface(with: (any AppMailboxProtocol).self)
        let onAvailable = onConnectionAvailable
        newConnection.invalidationHandler = { [weak self] in
            self?.removeConnection(newConnection)
            onAvailable(nil)
        }
        newConnection.interruptionHandler = { [weak self] in
            self?.removeConnection(newConnection)
            onAvailable(nil)
        }
        activeConnectionsLock.lock()
        activeConnections.append(newConnection)
        activeConnectionsLock.unlock()
        newConnection.resume()
        let holder = makeHolder(for: newConnection)
        onConnectionAvailable(holder)
        return true
    }

    private func removeConnection(_ connection: NSXPCConnection) {
        activeConnectionsLock.lock()
        activeConnections.removeAll { $0 === connection }
        activeConnectionsLock.unlock()
    }

    private func makeHolder(for connection: NSXPCConnection) -> ConnectionHolder {
        // Capture only what's needed; the closure crosses into the
        // dispatcher actor so it must be Sendable.
        let weakConnection = WeakConnection(connection: connection)
        return ConnectionHolder { item, completion in
            guard let conn = weakConnection.value else {
                completion(false, "connection_invalidated")
                return
            }
            let proxy = conn.remoteObjectProxyWithErrorHandler { error in
                logger.info("agent->app proxy error: \(error.localizedDescription)")
                completion(false, "connection_invalidated")
            } as? any AppMailboxProtocol
            guard let proxy else {
                completion(false, "connection_invalidated")
                return
            }
            proxy.deliverMailboxItem(item, reply: { success, reason in
                completion(success, reason)
            })
        }
    }
}

// `@unchecked Sendable` (CLAUDE.md §4.5 #2): wraps a weak reference to
// `NSXPCConnection`, which is not Sendable. The wrapper exists to let
// `ConnectionHolder`'s Sendable closure observe the connection's lifetime
// without retaining it. Thread safety: the only stored state is a `weak var`
// pointing at an Apple-managed connection; reads observe the standard ARC
// release semantics, the closure call sites are all on the XPC runtime's
// queues which Apple documents as serialised per connection.
private final class WeakConnection: @unchecked Sendable {
    weak var value: NSXPCConnection?
    init(connection: NSXPCConnection) {
        value = connection
    }
}

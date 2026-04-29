import Foundation
import Network
import TermuraRemoteProtocol

public actor LANTransport: RemoteTransport {
    public nonisolated let name: String
    private let serviceType: String
    private let codec: any RemoteCodec
    private let listenerQueue: DispatchQueue
    private var listener: NWListener?
    private var connections: [UUID: LANConnection] = [:]
    private var handler: (any EnvelopeHandler)?

    public init(
        name: String,
        serviceType: String = "_termura-remote._tcp",
        codec: any RemoteCodec = JSONRemoteCodec()
    ) {
        self.name = name
        self.serviceType = serviceType
        self.codec = codec
        self.listenerQueue = DispatchQueue(label: "termura.remote.lan.listener")
    }

    public func start(handler: any EnvelopeHandler) async throws {
        guard listener == nil else { throw TransportError.alreadyRunning }
        self.handler = handler

        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            self.handler = nil
            throw TransportError.bindFailure(reason: error.localizedDescription)
        }
        newListener.service = NWListener.Service(name: name, type: serviceType)
        newListener.newConnectionHandler = { [weak self] connection in
            Task { await self?.accept(connection) }
        }
        newListener.start(queue: listenerQueue)
        listener = newListener
    }

    public func stop() async {
        for connection in connections.values {
            await connection.close()
        }
        connections.removeAll()
        listener?.cancel()
        listener = nil
        handler = nil
    }

    public func activeConnectionCount() -> Int {
        connections.count
    }

    private func accept(_ connection: NWConnection) async {
        guard let handler else {
            connection.cancel()
            return
        }
        let session = LANConnection(connection: connection, codec: codec)
        connections[session.channelId] = session
        let proxy = ConnectionHandlerProxy(downstream: handler) { [weak self] channelId in
            await self?.removeConnection(channelId: channelId)
        }
        await session.start(handler: proxy)
    }

    private func removeConnection(channelId: UUID) {
        connections.removeValue(forKey: channelId)
    }
}

private struct ConnectionHandlerProxy: EnvelopeHandler {
    let downstream: any EnvelopeHandler
    let onClose: @Sendable (UUID) async -> Void

    func handle(envelope: Envelope, replyChannel: any ReplyChannel) async {
        await downstream.handle(envelope: envelope, replyChannel: replyChannel)
    }

    func connectionClosed(channelId: UUID) async {
        await onClose(channelId)
        await downstream.connectionClosed(channelId: channelId)
    }
}

import Foundation
import Network
import TermuraRemoteProtocol

public actor WebSocketClientTransport: ClientTransport {
    public struct Endpoint: Sendable, Equatable {
        public let host: String
        public let port: UInt16

        public init(host: String, port: UInt16) {
            self.host = host
            self.port = port
        }
    }

    /// Captures both styles of connection target so the transport can be
    /// constructed either from a manually-typed host:port or from a Bonjour
    /// browse result (which yields an opaque `NWEndpoint`).
    private enum Target: Sendable {
        case hostPort(host: String, port: UInt16)
        case rawEndpoint(NWEndpoint)
    }

    nonisolated let codec: any RemoteCodec
    private let target: Target
    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var isConnected = false

    public init(endpoint: Endpoint, codec: any RemoteCodec = JSONRemoteCodec()) {
        self.target = .hostPort(host: endpoint.host, port: endpoint.port)
        self.codec = codec
        self.queue = DispatchQueue(label: "termura.remote.client.\(endpoint.host)")
    }

    /// Build a transport from a `NWEndpoint` that came out of `LANBrowser` /
    /// `NWBrowser`. The browse result already encodes the resolved peer, so
    /// the caller doesn't need to know hostname or port — including the case
    /// where the LAN listener is bound to an ephemeral port.
    public init(nwEndpoint: NWEndpoint, codec: any RemoteCodec = JSONRemoteCodec()) {
        self.target = .rawEndpoint(nwEndpoint)
        self.codec = codec
        self.queue = DispatchQueue(label: "termura.remote.client.bonjour")
    }

    public func connect() async throws {
        guard connection == nil else { return }
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

        let nwConnection: NWConnection
        switch target {
        case let .hostPort(host, port):
            nwConnection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? .any,
                using: parameters
            )
        case let .rawEndpoint(endpoint):
            nwConnection = NWConnection(to: endpoint, using: parameters)
        }
        try await waitForReady(connection: nwConnection)
        self.connection = nwConnection
        self.isConnected = true
    }

    public func send(_ envelope: Envelope) async throws {
        guard isConnected, let connection else { throw ClientTransportError.notConnected }
        let data = try codec.encode(envelope)
        try await sendRaw(data: data, on: connection)
    }

    public func receive() async throws -> Envelope {
        guard isConnected, let connection else { throw ClientTransportError.notConnected }
        return try await receiveOne(on: connection, codec: codec)
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        isConnected = false
    }

    private func waitForReady(connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: ClientTransportError.connectFailure(reason: error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: ClientTransportError.connectFailure(reason: "cancelled before ready"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func sendRaw(data: Data, on connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let metadata = NWProtocolWebSocket.Metadata(opcode: .binary)
            let context = NWConnection.ContentContext(identifier: "envelope", metadata: [metadata])
            connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: ClientTransportError.sendFailure(reason: error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private nonisolated func receiveOne(on connection: NWConnection, codec: any RemoteCodec) async throws -> Envelope {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Envelope, any Error>) in
            connection.receiveMessage { content, _, _, error in
                if let error {
                    continuation.resume(throwing: ClientTransportError.receiveFailure(reason: error.localizedDescription))
                    return
                }
                guard let data = content, !data.isEmpty else {
                    continuation.resume(throwing: ClientTransportError.receiveFailure(reason: "empty frame"))
                    return
                }
                do {
                    let envelope = try codec.decode(Envelope.self, from: data)
                    continuation.resume(returning: envelope)
                } catch {
                    continuation.resume(throwing: ClientTransportError.decodeFailure(reason: String(describing: error)))
                }
            }
        }
    }
}

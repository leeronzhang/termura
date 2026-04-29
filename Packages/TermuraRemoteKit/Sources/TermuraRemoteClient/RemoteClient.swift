import Foundation
import TermuraRemoteProtocol

public actor RemoteClient {
    public enum State: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case disconnecting
    }

    private let transport: any ClientTransport
    private let codec: any RemoteCodec
    private(set) public var state: State = .disconnected
    private var receiveTask: Task<Void, Never>?
    private var inboxContinuation: AsyncStream<Envelope>.Continuation?

    public init(transport: any ClientTransport, codec: any RemoteCodec = JSONRemoteCodec()) {
        self.transport = transport
        self.codec = codec
    }

    public func connect() async throws {
        guard state == .disconnected else {
            throw RemoteClientError.invalidState(current: state)
        }
        state = .connecting
        do {
            try await transport.connect()
        } catch {
            state = .disconnected
            throw error
        }
        state = .connected
    }

    public func disconnect() async {
        guard state == .connected else { return }
        state = .disconnecting
        receiveTask?.cancel()
        receiveTask = nil
        await transport.disconnect()
        inboxContinuation?.finish()
        inboxContinuation = nil
        state = .disconnected
    }

    public func send(_ envelope: Envelope) async throws {
        guard state == .connected else { throw RemoteClientError.notConnected }
        try await transport.send(envelope)
    }

    public func sendCommand(_ command: RemoteCommand) async throws {
        let envelope = try Envelope.encode(command, kind: .cmdExec, codec: codec)
        try await send(envelope)
    }

    public func requestSessionList() async throws {
        let envelope = Envelope(kind: .sessionListRequest, payload: Data())
        try await send(envelope)
    }

    public func ping() async throws {
        let envelope = Envelope(kind: .ping, payload: Data())
        try await send(envelope)
    }

    public func inbox() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            inboxContinuation = continuation
            receiveTask = Task { [transport, codec] in
                await Self.receiveLoop(transport: transport, codec: codec, continuation: continuation)
            }
            continuation.onTermination = { _ in
                Task { [weak self] in await self?.markInboxClosed() }
            }
        }
    }

    private func markInboxClosed() {
        inboxContinuation = nil
    }

    private static func receiveLoop(
        transport: any ClientTransport,
        codec _: any RemoteCodec,
        continuation: AsyncStream<Envelope>.Continuation
    ) async {
        while !Task.isCancelled {
            do {
                let envelope = try await transport.receive()
                continuation.yield(envelope)
            } catch {
                continuation.finish()
                return
            }
        }
        continuation.finish()
    }
}

public enum RemoteClientError: Error, Sendable, Equatable {
    case invalidState(current: RemoteClient.State)
    case notConnected
}

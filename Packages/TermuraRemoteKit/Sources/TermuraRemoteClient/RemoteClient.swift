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
    /// Always-JSON codec used for handshake-phase envelopes (`pair_init`,
    /// `pair_complete`, `error`, `ping`/`pong`). Held alongside
    /// `messagepackCodec` so `setActiveCodec` can flip without re-allocating.
    private let handshakeCodec: any RemoteCodec
    private let messagepackCodec: any RemoteCodec
    /// Codec used to encode `cmd_*` inner payloads after the
    /// `PairingCompleteAck` arrives. Stays at `handshakeCodec` until
    /// `setActiveCodec(_:)` is called, which mirrors the per-channel phase
    /// transition the server-side router does. Pre-PR8 this was a `let`
    /// initialised once and never updated, so a `messagepack`-negotiated
    /// connection silently kept JSON-encoding `cmd_exec` payloads — the
    /// server then rejected them as `Bad command payload` and the client
    /// hung waiting for an ack/snapshot that never came.
    private var activeCodec: any RemoteCodec
    public private(set) var state: State = .disconnected
    private var receiveTask: Task<Void, Never>?
    private var inboxContinuation: AsyncStream<Envelope>.Continuation?

    public init(transport: any ClientTransport, codec: any RemoteCodec = JSONRemoteCodec()) {
        self.transport = transport
        handshakeCodec = codec
        messagepackCodec = MessagePackRemoteCodec()
        activeCodec = codec
    }

    /// Flip the inner-payload codec to the value the server selected during
    /// pair handshake. Call exactly once per connection, between the
    /// `PairingCompleteAck` decode and the moment the UI lets the user issue
    /// commands — both sides must be on the agreed codec before the first
    /// `cmd_exec` envelope crosses the wire. Idempotent on equal kinds so a
    /// duplicated ack delivery doesn't churn the codec instance.
    public func setActiveCodec(_ kind: CodecKind) {
        switch kind {
        case .json:
            activeCodec = handshakeCodec
        case .messagepack:
            activeCodec = messagepackCodec
        }
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
        let envelope = try Envelope.encode(command, kind: .cmdExec, codec: activeCodec)
        try await send(envelope)
    }

    public func requestSessionList() async throws {
        let envelope = Envelope(kind: .sessionListRequest, payload: Data())
        try await send(envelope)
    }

    /// Sends a `.rejoin` envelope to resume an authenticated session on a
    /// fresh transport channel without consuming a new invitation. The
    /// caller (typically `RemoteStore.reconnect`) is expected to observe
    /// `inbox()` for the matching `.rejoinAck`, decode it, and call
    /// `setActiveCodec(_:)` with the negotiated codec — mirroring the
    /// existing `pairInit` / `pairComplete` round-trip pattern. The
    /// envelope is always JSON-encoded because the channel is still in
    /// the handshake phase server-side.
    public func rejoin(_ request: RejoinRequest) async throws {
        let envelope = try Envelope.encode(request, kind: .rejoin, codec: handshakeCodec)
        try await send(envelope)
    }

    public func ping() async throws {
        let envelope = Envelope(kind: .ping, payload: Data())
        try await send(envelope)
    }

    public func inbox() -> AsyncStream<Envelope> {
        AsyncStream { continuation in
            inboxContinuation = continuation
            receiveTask = Task { [transport] in
                await Self.receiveLoop(transport: transport, continuation: continuation)
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

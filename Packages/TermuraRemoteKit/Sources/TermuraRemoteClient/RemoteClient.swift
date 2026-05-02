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
    /// pair handshake. Wave 2 — `inbox()` now drives this internally on
    /// every `.pairComplete` / `.rejoinAck` envelope, so callers (the iOS
    /// `RemoteStore`, harness tests) no longer have to remember to call
    /// it. Kept public + idempotent so existing call sites still compile
    /// and so tests that don't drive a real handshake can still seed the
    /// codec directly.
    public func setActiveCodec(_ kind: CodecKind) {
        switch kind {
        case .json:
            activeCodec = handshakeCodec
        case .messagepack:
            activeCodec = messagepackCodec
        }
    }

    /// Wave 2 — peeks at every inbound envelope before yielding to the
    /// inbox stream and self-applies the codec flip when it sees a
    /// pair-handshake terminator. Pre-Wave-2 the caller had to decode
    /// the ack itself and remember to invoke `setActiveCodec(_:)`; a
    /// fresh PR (or a refactor that broke the call site) silently kept
    /// JSON-encoding subsequent business envelopes, the server then
    /// rejected them as `Bad command payload`, and the UI hung waiting
    /// for an ack/snapshot that never came. Decoding failures here are
    /// non-fatal — the envelope is still yielded so the caller's own
    /// decode path sees the failure and can fail the pair flow.
    private func applyImplicitPhaseTransitions(envelope: Envelope) {
        switch envelope.kind {
        case .pairComplete:
            decodeAndApplyAck(PairingCompleteAck.self, from: envelope) { $0.negotiatedCodec }
        case .rejoinAck:
            decodeAndApplyAck(RejoinAck.self, from: envelope) { $0.negotiatedCodec }
        default:
            break
        }
    }

    /// Helper for `applyImplicitPhaseTransitions`. Decodes the inner
    /// payload as `T` using the handshake codec and, on success, drives
    /// `setActiveCodec` with the codec the closure extracts. Decode
    /// failures are intentionally swallowed here — the envelope is
    /// still yielded to the inbox so the caller's own decode path can
    /// observe the failure and fail the pair flow.
    private func decodeAndApplyAck<T: Decodable>(
        _ type: T.Type,
        from envelope: Envelope,
        codec extract: (T) -> CodecKind
    ) {
        let decoded: T
        do {
            decoded = try envelope.decode(T.self, codec: handshakeCodec)
        } catch {
            // Non-critical: the caller surfaces the same decode error
            // through its own handshake-complete / rejoin-ack handler
            // (e.g. `RemoteStore+Pairing.handlePairComplete`), which is
            // where the user-visible "pair handshake response unreadable"
            // error originates. Swallowing here keeps RemoteClient's
            // peek path side-effect-free on bad input.
            return
        }
        setActiveCodec(extract(decoded))
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
            receiveTask = Task { [weak self] in
                await self?.receiveLoop(continuation: continuation)
            }
            continuation.onTermination = { _ in
                Task { [weak self] in await self?.markInboxClosed() }
            }
        }
    }

    private func markInboxClosed() {
        inboxContinuation = nil
    }

    private func receiveLoop(continuation: AsyncStream<Envelope>.Continuation) async {
        while !Task.isCancelled {
            do {
                let envelope = try await transport.receive()
                applyImplicitPhaseTransitions(envelope: envelope)
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

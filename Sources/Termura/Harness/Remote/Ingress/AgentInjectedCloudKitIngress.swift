// PR8 §3.6 — agent → app business kernel. Receives an
// `AgentMailboxItem` from the LaunchAgent (via XPC), decodes the
// payload according to `payloadKind`, classifies the source through
// `TrustedSourceGate`, and either drives the existing router via
// `primeAuthenticatedChannel` + `handle(...)` or drops with a tagged
// `AppMailboxReply` so the agent dispatcher can decide
// delete/advance/quarantine. See §7.2 error classification table.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "AgentInjectedCloudKitIngress")

actor AgentInjectedCloudKitIngress {
    private let router: RemoteEnvelopeRouter
    private let gate: TrustedSourceGate
    private let pairKeyStore: any PairKeyStore
    private let gateway: any CloudKitDatabaseGateway
    private let macDeviceId: UUID
    private let codec: any RemoteCodec
    private let clock: @Sendable () -> Date
    private var inFlight: [UUID: Task<Void, Never>] = [:]
    private var isShutdown = false

    init(
        router: RemoteEnvelopeRouter,
        gate: TrustedSourceGate,
        pairKeyStore: any PairKeyStore,
        gateway: any CloudKitDatabaseGateway,
        macDeviceId: UUID,
        codec: any RemoteCodec,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.router = router
        self.gate = gate
        self.pairKeyStore = pairKeyStore
        self.gateway = gateway
        self.macDeviceId = macDeviceId
        self.codec = codec
        self.clock = clock
    }

    /// Single entry point invoked by `AppMailboxXPCBridge` after it
    /// rebuilds an `AgentMailboxItem` from the on-the-wire
    /// `XPCMailboxItem`. Returns the reply that the bridge then
    /// translates into the `(BOOL, NSString *)` reply block.
    func ingest(item: AgentMailboxItem) async -> AppMailboxReply {
        if isShutdown { return .retry("shutdown") }
        guard item.schemaVersion == AgentMailboxItem.currentSchemaVersion else {
            logger.warning("schema mismatch: expected \(AgentMailboxItem.currentSchemaVersion), got \(item.schemaVersion)")
            return .retry("schema_mismatch")
        }
        let envelope: Envelope
        switch item.payloadKind {
        case .plaintext:
            do {
                envelope = try JSONDecoder().decode(Envelope.self, from: item.payloadData)
            } catch {
                logger.warning("plaintext decode failed: \(error.localizedDescription)")
                return .retry("decode_failed")
            }
        case .cipher:
            switch await decodeCipher(item: item) {
            case let .ok(value):
                envelope = value
            case let .reply(reply):
                return reply
            }
        }
        return await dispatch(envelope: envelope, sourceDeviceId: item.sourceDeviceId)
    }

    /// Cancels in-flight work and rejects further `ingest` calls.
    func shutdown() async {
        isShutdown = true
        for (_, task) in inFlight {
            task.cancel()
        }
        inFlight.removeAll()
    }

    // MARK: - Cipher decoding

    private enum CipherDecodeOutcome {
        case ok(Envelope)
        case reply(AppMailboxReply)
    }

    private func decodeCipher(item: AgentMailboxItem) async -> CipherDecodeOutcome {
        let blob: CipherBlob
        do {
            blob = try JSONDecoder().decode(CipherBlob.self, from: item.payloadData)
        } catch {
            logger.warning("cipher blob decode failed: \(error.localizedDescription)")
            return .reply(.retry("decode_failed"))
        }
        let key: PairKey?
        do {
            key = try await pairKeyStore.key(forPairing: blob.keyId)
        } catch {
            logger.warning("pair key lookup error: \(error.localizedDescription)")
            return .reply(.retry("pairkey_missing"))
        }
        guard let pairKey = key else {
            logger.warning("pair key not found for keyId \(blob.keyId)")
            return .reply(.retry("pairkey_missing"))
        }
        do {
            let envelope = try CloudEnvelopeCrypto.open(blob, with: pairKey, codec: codec)
            return .ok(envelope)
        } catch {
            logger.warning("cipher open failed (terminal): \(error.localizedDescription)")
            return .reply(.terminal("cipher_open_failed"))
        }
    }

    // MARK: - Routing

    private func dispatch(envelope: Envelope, sourceDeviceId: UUID) async -> AppMailboxReply {
        let classification = await gate.classify(sourceDeviceId: sourceDeviceId)
        if envelope.kind.isAllowedDuringHandshake {
            return await handleHandshake(envelope: envelope, sourceDeviceId: sourceDeviceId)
        }
        switch classification {
        case let .knownActive(pairedDeviceId, cloudSourceDeviceId, codec, pairingId):
            return await handleBusiness(
                envelope: envelope,
                pairedDeviceId: pairedDeviceId,
                cloudSourceDeviceId: cloudSourceDeviceId,
                negotiatedCodec: codec,
                pairingId: pairingId
            )
        case .knownRevoked:
            return .terminal("revoked")
        case .unknown:
            return .terminal("unknown_source")
        }
    }

    private func handleHandshake(envelope: Envelope, sourceDeviceId: UUID) async -> AppMailboxReply {
        // Handshake envelopes (pair_init / pair_complete / error /
        // ping / pong) carry plaintext payloads — by design they
        // travel before any pair key exists. Reply must therefore
        // also be plaintext: write a `CloudKitEnvelopeRecord` with
        // `.plaintext(envelope)` payload so the iPhone can finish
        // the handshake.
        let reply = AgentVirtualHandshakeReplyChannel(
            channelId: sourceDeviceId,
            transportDeviceId: macDeviceId,
            peerDeviceId: sourceDeviceId,
            gateway: gateway,
            clock: clock
        )
        let task = Task {
            await self.router.handle(envelope: envelope, replyChannel: reply)
        }
        inFlight[envelope.id] = task
        await task.value
        inFlight.removeValue(forKey: envelope.id)
        return .ok
    }

    private func handleBusiness(
        envelope: Envelope,
        pairedDeviceId: UUID,
        cloudSourceDeviceId: UUID,
        negotiatedCodec: CodecKind,
        pairingId: UUID?
    ) async -> AppMailboxReply {
        guard let pairingId else {
            logger.warning("trusted device but no pairingId; cipher reply impossible")
            return .terminal("pairkey_missing")
        }
        await router.primeAuthenticatedChannel(
            channelId: cloudSourceDeviceId,
            deviceId: pairedDeviceId,
            negotiatedCodec: negotiatedCodec
        )
        let reply = AgentVirtualReplyChannel(
            transportDeviceId: macDeviceId,
            peerDeviceId: cloudSourceDeviceId,
            pairingId: pairingId,
            gateway: gateway,
            pairKeyStore: pairKeyStore,
            codec: codec,
            clock: clock
        )
        let task = Task {
            await self.router.handle(envelope: envelope, replyChannel: reply)
        }
        inFlight[envelope.id] = task
        await task.value
        inFlight.removeValue(forKey: envelope.id)
        return .ok
    }
}

/// Handshake-phase reply channel. The router writes `pair_complete`
/// / `error` / `pong` envelopes; we serialise them as plaintext
/// `CloudKitEnvelopeRecord`s and `gateway.save` them so the iPhone
/// can finish the handshake. No pair key is needed because handshake
/// envelopes ride in plaintext by design (the symmetric key only
/// exists after `pair_complete`).
private actor AgentVirtualHandshakeReplyChannel: ReplyChannel {
    nonisolated let channelId: UUID
    private let transportDeviceId: UUID
    private let peerDeviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let clock: @Sendable () -> Date
    private var isOpen = true

    init(
        channelId: UUID,
        transportDeviceId: UUID,
        peerDeviceId: UUID,
        gateway: any CloudKitDatabaseGateway,
        clock: @escaping @Sendable () -> Date
    ) {
        self.channelId = channelId
        self.transportDeviceId = transportDeviceId
        self.peerDeviceId = peerDeviceId
        self.gateway = gateway
        self.clock = clock
    }

    func send(_ envelope: Envelope) async throws {
        guard isOpen else { return }
        let record = CloudKitEnvelopeRecord(
            id: UUID().uuidString,
            payload: .plaintext(envelope),
            targetDeviceId: peerDeviceId,
            sourceDeviceId: transportDeviceId,
            createdAt: clock()
        )
        try await gateway.save(record)
    }

    func close() async {
        isOpen = false
    }
}

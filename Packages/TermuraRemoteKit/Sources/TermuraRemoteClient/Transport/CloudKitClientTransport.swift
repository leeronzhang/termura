import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitClientTransport")

/// CloudKit-backed `ClientTransport` mirror of `CloudKitTransport`. Designed
/// for cross-network operation: when the LAN socket is unavailable the iOS
/// client falls back to writing/reading records in the shared iCloud Private
/// Database. Push-driven wake-ups call `ingestPushNotification()` to bypass
/// the poll interval; otherwise a background Task ticks at `pollInterval`.
///
/// OWNER: caller (typically `RemoteStore`)
/// CANCEL: `disconnect()` cancels the poll Task and resumes pending receivers
/// TEARDOWN: drop reference; actor cleanup runs on disconnect
public actor CloudKitClientTransport: ClientTransport {
    public struct Configuration: Sendable {
        public let pollInterval: Duration

        public init(pollInterval: Duration = .seconds(60)) {
            self.pollInterval = pollInterval
        }
    }

    nonisolated let codec: any RemoteCodec
    private let localDeviceId: UUID
    private let peerDeviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let pairKeyStore: (any PairKeyStore)?
    private let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var pollingTask: Task<Void, Never>?
    private var lastSeen: Date = .distantPast
    private var queue: [Envelope] = []
    private var waiters: [CheckedContinuation<Envelope, any Error>] = []
    private var isConnected = false
    /// PR7 — `pairingId` of the active relationship. Set after iOS sees
    /// `PairingCompleteAck` (RemoteStore drives it). While `nil`, `send`
    /// writes plaintext records (the bootstrap path used by the
    /// CloudKit-mode initial pair); once set, `send` seals via the
    /// matching `PairKey`.
    private var activePairingId: UUID?

    public init(
        localDeviceId: UUID,
        peerDeviceId: UUID,
        gateway: any CloudKitDatabaseGateway,
        pairKeyStore: (any PairKeyStore)? = nil,
        codec: any RemoteCodec = JSONRemoteCodec(),
        configuration: Configuration = Configuration(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.localDeviceId = localDeviceId
        self.peerDeviceId = peerDeviceId
        self.gateway = gateway
        self.pairKeyStore = pairKeyStore
        self.codec = codec
        self.configuration = configuration
        self.clock = clock
    }

    /// Switches `send` from plaintext-bootstrap mode to encrypted mode.
    /// Called by `RemoteStore` once `PairingCompleteAck.pairingId` lands
    /// and the matching `PairKey` is in `pairKeyStore`. Passing `nil`
    /// reverts to plaintext (e.g. on disconnect).
    public func setActivePairingId(_ id: UUID?) {
        activePairingId = id
    }

    public func connect() async throws {
        guard !isConnected else { return }
        do {
            let initial = try await gateway.fetch(targetDeviceId: localDeviceId, since: .distantPast)
            lastSeen = initial.map(\.createdAt).max() ?? clock()
        } catch {
            // Mirror the diagnostic surface `pollOnce` already provides
            // (`logger.error("Poll failed: …")`). Without this, a failed
            // initial fetch only surfaces through the thrown error;
            // `Console.app` / `log stream` saw nothing, so users had no
            // way to recover the underlying CKError reason after the
            // toast scrolled away.
            logger.error(
                "CloudKit connect fetch failed: \(error.localizedDescription, privacy: .public)"
            )
            throw ClientTransportError.connectFailure(reason: error.localizedDescription)
        }
        isConnected = true
        let interval = configuration.pollInterval
        pollingTask = Task { [weak self] in
            await self?.runPollLoop(interval: interval)
        }
    }

    public func send(_ envelope: Envelope) async throws {
        guard isConnected else { throw ClientTransportError.notConnected }
        let payload: CloudKitEnvelopeRecord.Payload
        if let pairKey = await resolvePairKey() {
            do {
                let blob = try CloudEnvelopeCrypto.seal(
                    envelope: envelope,
                    with: pairKey,
                    codec: codec
                )
                payload = .cipher(blob)
            } catch {
                throw ClientTransportError.sendFailure(
                    reason: "seal failed: \(error.localizedDescription)"
                )
            }
        } else {
            // Bootstrap path: no key yet. The Mac's CloudKit transport
            // accepts `.plaintext` only for the handshake-allowed kinds;
            // anything else gets dropped server-side.
            payload = .plaintext(envelope)
        }
        let record = CloudKitEnvelopeRecord(
            id: UUID().uuidString,
            payload: payload,
            targetDeviceId: peerDeviceId,
            sourceDeviceId: localDeviceId,
            createdAt: clock()
        )
        do {
            try await gateway.save(record)
        } catch {
            throw ClientTransportError.sendFailure(reason: error.localizedDescription)
        }
    }

    private func resolvePairKey() async -> PairKey? {
        guard let id = activePairingId, let store = pairKeyStore else { return nil }
        do {
            return try await store.key(forPairing: id)
        } catch {
            logger.warning("PairKey lookup failed for \(id): \(error.localizedDescription)")
            return nil
        }
    }

    public func receive() async throws -> Envelope {
        guard isConnected else { throw ClientTransportError.notConnected }
        if !queue.isEmpty {
            return queue.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        pollingTask?.cancel()
        pollingTask = nil
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(throwing: ClientTransportError.notConnected)
        }
        queue.removeAll()
    }

    /// Triggered by silent push delegate; forces an immediate poll instead of
    /// waiting for the next tick.
    public func ingestPushNotification() async {
        _ = await pollOnce()
    }

    /// One-shot poll triggered by `BGTaskScheduler`. Returns `true` when the
    /// gateway answered without error (whether or not new records were
    /// found), `false` when the network/gateway call failed. Callers feed
    /// the result straight into `BGTask.setTaskCompleted(success:)`.
    ///
    /// OWNER: caller (BGTask handler in iOS app)
    /// CANCEL: BGTask `expirationHandler` should call `disconnect()` if it
    ///         needs to abort mid-fetch — `pollOnce` itself is short-lived
    /// TEARDOWN: nothing to release; the transport keeps living
    public func performBackgroundPoll() async -> Bool {
        guard isConnected else { return false }
        return await pollOnce()
    }

    private func runPollLoop(interval: Duration) async {
        while !Task.isCancelled {
            _ = await pollOnce()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    @discardableResult
    private func pollOnce() async -> Bool {
        guard isConnected else { return false }
        let records: [CloudKitEnvelopeRecord]
        do {
            records = try await gateway.fetch(targetDeviceId: localDeviceId, since: lastSeen)
        } catch let CloudKitGatewayError.unsupportedSchema(version) {
            // Skip the entire batch but record the version so a stuck
            // v1 leftover surfaces in `log stream`. Same handling as the
            // server CloudKitTransport.
            logger.warning("Skipping fetch batch with unsupported schemaVersion=\(version)")
            return false
        } catch {
            logger.error("Poll failed: \(error.localizedDescription)")
            return false
        }
        for record in records {
            switch record.payload {
            case let .plaintext(envelope):
                deliver(envelope: envelope)
            case let .cipher(blob):
                if let envelope = await openCipher(blob) {
                    deliver(envelope: envelope)
                }
                // Drop unreadable cipher records below — same warning
                // path as `openCipher` already logged.
            }
            if record.createdAt > lastSeen {
                lastSeen = record.createdAt
            }
            do {
                try await gateway.delete(id: record.id)
            } catch {
                logger.warning("Failed to delete consumed record \(record.id): \(error.localizedDescription)")
            }
        }
        return true
    }

    private func openCipher(_ blob: CipherBlob) async -> Envelope? {
        guard let store = pairKeyStore else {
            logger.warning("CipherBlob received but no PairKeyStore configured; dropping record")
            return nil
        }
        let pairKey: PairKey?
        do {
            pairKey = try await store.key(forPairing: blob.keyId)
        } catch {
            logger.warning("PairKey lookup failed for \(blob.keyId): \(error.localizedDescription)")
            return nil
        }
        guard let pairKey else {
            logger.warning("No PairKey for keyId=\(blob.keyId); dropping record")
            return nil
        }
        do {
            return try CloudEnvelopeCrypto.open(blob, with: pairKey, codec: codec)
        } catch {
            logger.warning("CloudEnvelopeCrypto.open failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func deliver(envelope: Envelope) {
        if waiters.isEmpty {
            queue.append(envelope)
            return
        }
        let waiter = waiters.removeFirst()
        waiter.resume(returning: envelope)
    }
}

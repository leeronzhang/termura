import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitTransport")

/// CloudKit-backed `RemoteTransport` for cross-network operation. Polls the
/// inbox at `pollInterval` and processes records via the injected gateway.
/// Push-driven wake-ups (silent APNs) call `ingestPushNotification()` to
/// trigger an immediate poll without waiting for the next tick.
///
/// OWNER: caller (typically `RemoteServerHarness`)
/// CANCEL: `stop()` cancels the poll Task and clears handler/channels
/// TEARDOWN: drop reference; actor cleanup runs on stop
public actor CloudKitTransport: RemoteTransport {
    public struct Configuration: Sendable {
        public let pollInterval: Duration

        public init(pollInterval: Duration = .seconds(60)) {
            self.pollInterval = pollInterval
        }
    }

    public nonisolated let name: String
    private let deviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let pairKeyStore: (any PairKeyStore)?
    private let codec: any RemoteCodec
    private let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var pollingTask: Task<Void, Never>?
    private var handler: (any EnvelopeHandler)?
    private var lastSeen: Date = .distantPast
    private var channels: [UUID: CloudKitReplyChannel] = [:]

    public init(
        name: String,
        deviceId: UUID,
        gateway: any CloudKitDatabaseGateway,
        pairKeyStore: (any PairKeyStore)? = nil,
        codec: any RemoteCodec = JSONRemoteCodec(),
        configuration: Configuration = Configuration(),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.name = name
        self.deviceId = deviceId
        self.gateway = gateway
        self.pairKeyStore = pairKeyStore
        self.codec = codec
        self.configuration = configuration
        self.clock = clock
    }

    /// Switches the per-peer reply channel from plaintext-bootstrap mode
    /// to encrypted mode by binding it to a specific `pairingId`. The
    /// router calls this after `PairingCompleteAck` is queued so every
    /// subsequent reply seals via the matching `PairKey`. No-op if the
    /// channel hasn't been created yet — sends will pick up the right
    /// pairingId once they do.
    public func setActivePairingId(_ id: UUID?, forSourceDeviceId source: UUID) async {
        await channels[source]?.setActivePairingId(id)
    }

    public func start(handler: any EnvelopeHandler) async throws {
        guard pollingTask == nil else { throw TransportError.alreadyRunning }
        self.handler = handler
        // Establish the cursor at the latest existing record so we don't replay
        // an iPhone's pre-pair traffic on every Mac restart.
        do {
            let initial = try await gateway.fetch(targetDeviceId: deviceId, since: .distantPast)
            if let max = initial.map(\.createdAt).max() {
                lastSeen = max
            } else {
                lastSeen = clock()
            }
        } catch {
            self.handler = nil
            throw TransportError.bindFailure(reason: error.localizedDescription)
        }
        let interval = configuration.pollInterval
        pollingTask = Task { [weak self] in
            await self?.runPollLoop(interval: interval)
        }
    }

    public func stop() async {
        pollingTask?.cancel()
        pollingTask = nil
        handler = nil
        for channel in channels.values {
            await channel.close()
        }
        channels.removeAll()
    }

    /// Triggered by silent push (APNs) — bypasses the poll interval.
    public func ingestPushNotification() async {
        await pollOnce()
    }

    private func runPollLoop(interval: Duration) async {
        while !Task.isCancelled {
            await pollOnce()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    private func pollOnce() async {
        guard let handler else { return }
        let records: [CloudKitEnvelopeRecord]
        do {
            records = try await gateway.fetch(targetDeviceId: deviceId, since: lastSeen)
        } catch let CloudKitGatewayError.unsupportedSchema(version) {
            // PR7 — v1 records (pre-encryption) are intentionally rejected
            // on read. We can't reach the offending recordId from here
            // without the gateway reporting it, so the warning surfaces
            // the version and the next poll will see a fresh batch
            // (the live gateway aborts the entire fetch). The legacy
            // record stays in CloudKit until manual cleanup or a future
            // gateway pass that reports per-record errors.
            logger.warning("Skipping fetch batch with unsupported schemaVersion=\(version)")
            return
        } catch {
            logger.error("Poll failed: \(error.localizedDescription)")
            return
        }
        for record in records {
            await dispatch(record: record, handler: handler)
            if record.createdAt > lastSeen {
                lastSeen = record.createdAt
            }
        }
    }

    private func dispatch(record: CloudKitEnvelopeRecord, handler: any EnvelopeHandler) async {
        let envelope: Envelope
        switch record.payload {
        case let .plaintext(value):
            envelope = value
        case let .cipher(blob):
            guard let decrypted = await openCipher(blob) else {
                // Drop unreadable record (no key / wrong key / tampered).
                // Warning is logged inside `openCipher`; deletion below
                // keeps the mailbox clean so we don't re-fetch it on the
                // next poll.
                await deleteAfterDispatch(id: record.id)
                return
            }
            envelope = decrypted
        }
        let channel = channelFor(sourceDeviceId: record.sourceDeviceId)
        await handler.handle(envelope: envelope, replyChannel: channel)
        await deleteAfterDispatch(id: record.id)
    }

    private func deleteAfterDispatch(id: String) async {
        do {
            try await gateway.delete(id: id)
        } catch {
            logger.warning("Failed to delete consumed record \(id): \(error.localizedDescription)")
        }
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

    private func channelFor(sourceDeviceId: UUID) -> CloudKitReplyChannel {
        if let existing = channels[sourceDeviceId] { return existing }
        let channel = CloudKitReplyChannel(
            transportDeviceId: deviceId,
            peerDeviceId: sourceDeviceId,
            gateway: gateway,
            pairKeyStore: pairKeyStore,
            codec: codec,
            clock: clock
        )
        channels[sourceDeviceId] = channel
        return channel
    }
}

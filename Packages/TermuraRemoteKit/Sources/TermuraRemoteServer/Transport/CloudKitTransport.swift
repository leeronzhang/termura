import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitTransport")

/// CloudKit-backed `RemoteTransport` for cross-network operation. Polls the
/// inbox at `pollInterval` and processes records via the injected gateway.
/// Push-driven wake-ups (silent APNs) call `ingestPushNotification()` to
/// trigger an immediate poll without waiting for the next tick.
///
/// Wave 1 — poll failures now feed an exponential-backoff schedule + a
/// `pollHealth()` snapshot the harness/Settings UI can surface, so a
/// CloudKit outage stops looking to the user like "the app froze".
/// Cipher decode failures distinguish transient (Keychain locked /
/// first-unlock pending) from permanent (key missing / tampered);
/// transient outcomes leave the record in the mailbox for a future
/// unlocked run.
///
/// OWNER: caller (typically `RemoteServerHarness`)
/// CANCEL: `stop()` cancels the poll Task and clears handler/channels
/// TEARDOWN: drop reference; actor cleanup runs on stop
public actor CloudKitTransport: RemoteTransport {
    public struct Configuration: Sendable {
        public let pollInterval: Duration
        /// Maximum consecutive poll failures before the transport flags itself
        /// `.unhealthy`. Tuned to ~5 × 60s — long enough to ride out a Wi-Fi
        /// roam, short enough that a sustained CloudKit outage gets visible.
        public let healthFailureThreshold: Int
        /// Cap on the exponential backoff delay applied between poll
        /// attempts after consecutive failures.
        public let backoffCap: Duration

        public init(
            pollInterval: Duration = .seconds(60),
            healthFailureThreshold: Int = 5,
            backoffCap: Duration = .seconds(600)
        ) {
            self.pollInterval = pollInterval
            self.healthFailureThreshold = healthFailureThreshold
            self.backoffCap = backoffCap
        }
    }

    /// Poll-loop health summary. `unhealthy` flips on after
    /// `healthFailureThreshold` consecutive failures and clears the moment a
    /// poll succeeds; consumers (the harness, Settings UI) read it to surface
    /// "CloudKit unreachable" without polling the actor every tick.
    public struct PollHealth: Sendable, Equatable {
        public let isHealthy: Bool
        public let consecutiveFailures: Int
        public let lastFailureReason: String?

        public init(isHealthy: Bool, consecutiveFailures: Int, lastFailureReason: String? = nil) {
            self.isHealthy = isHealthy
            self.consecutiveFailures = consecutiveFailures
            self.lastFailureReason = lastFailureReason
        }

        public static let healthy = PollHealth(isHealthy: true, consecutiveFailures: 0)
    }

    public nonisolated let name: String
    private let deviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    /// Module-internal so the same-module `+CipherDecode` extension can
    /// reach the store without widening the public actor surface.
    let pairKeyStore: (any PairKeyStore)?
    /// Module-internal for the same reason as `pairKeyStore` above.
    let codec: any RemoteCodec
    private let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var pollingTask: Task<Void, Never>?
    private var handler: (any EnvelopeHandler)?
    private var lastSeen: Date = .distantPast
    private var channels: [UUID: CloudKitReplyChannel] = [:]
    private var consecutivePollFailures = 0
    private var lastPollFailureReason: String?

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

    /// Snapshot of the most recent poll outcome. Settings UI / harness
    /// can read this to surface "CloudKit unreachable" instead of leaving
    /// the user staring at a hung session list.
    public func pollHealth() -> PollHealth {
        PollHealth(
            isHealthy: consecutivePollFailures < configuration.healthFailureThreshold,
            consecutiveFailures: consecutivePollFailures,
            lastFailureReason: lastPollFailureReason
        )
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
        pollingTask = Task { [weak self] in
            await self?.runPollLoop()
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

    private func runPollLoop() async {
        while !Task.isCancelled {
            await pollOnce()
            do {
                try await Task.sleep(for: nextPollDelay())
            } catch {
                return
            }
        }
    }

    /// Computes the wait between this poll and the next. After a clean
    /// poll, `consecutivePollFailures == 0` and we sleep the configured
    /// interval. After failures we sleep `pollInterval × 2^(failures-1)`
    /// up to `backoffCap`, so a sustained CloudKit outage doesn't keep
    /// hammering the gateway every minute.
    private func nextPollDelay() -> Duration {
        guard consecutivePollFailures > 0 else { return configuration.pollInterval }
        let baseSeconds = Self.durationInSeconds(configuration.pollInterval)
        let multiplier = pow(2.0, Double(min(consecutivePollFailures - 1, 16)))
        let candidateSeconds = baseSeconds * multiplier
        let capSeconds = Self.durationInSeconds(configuration.backoffCap)
        let bounded = min(candidateSeconds, capSeconds)
        return .seconds(bounded)
    }

    private static func durationInSeconds(_ duration: Duration) -> Double {
        let comp = duration.components
        return Double(comp.seconds) + Double(comp.attoseconds) / 1.0e18
    }

    private func pollOnce() async {
        guard let handler else { return }
        let records: [CloudKitEnvelopeRecord]
        do {
            records = try await gateway.fetch(targetDeviceId: deviceId, since: lastSeen)
        } catch let CloudKitGatewayError.unsupportedSchema(version) {
            // PR7 — v1 records (pre-encryption) are intentionally rejected
            // on read. The transport skips the entire batch with a warning.
            // Schema mismatch is not a transport health concern (the
            // gateway is healthy; the data is stale), so we don't bump
            // the failure counter.
            logger.warning("Skipping fetch batch with unsupported schemaVersion=\(version)")
            recordPollSuccess()
            return
        } catch {
            recordPollFailure(reason: error.localizedDescription)
            return
        }
        for record in records {
            await dispatch(record: record, handler: handler)
            if record.createdAt > lastSeen {
                lastSeen = record.createdAt
            }
        }
        recordPollSuccess()
    }

    private func recordPollSuccess() {
        // Bind locally so the OSLog autoclosure interpolation does not
        // implicitly capture `self`; SwiftFormat's redundantSelf rule
        // strips explicit `self.` here, so the local is the only form
        // that satisfies both the compiler and the formatter.
        let failures = consecutivePollFailures
        if failures > 0 {
            logger.info("CloudKit poll recovered after \(failures) failures")
        }
        consecutivePollFailures = 0
        lastPollFailureReason = nil
    }

    private func recordPollFailure(reason: String) {
        consecutivePollFailures += 1
        lastPollFailureReason = reason
        let failures = consecutivePollFailures
        if failures >= configuration.healthFailureThreshold {
            logger.error("Poll failed (#\(failures)): \(reason, privacy: .public)")
        } else {
            logger.warning("Poll failed (#\(failures)): \(reason, privacy: .public)")
        }
    }

    private func dispatch(record: CloudKitEnvelopeRecord, handler: any EnvelopeHandler) async {
        let envelope: Envelope
        switch record.payload {
        case let .plaintext(value):
            envelope = value
        case let .cipher(blob):
            switch await openCipher(blob) {
            case let .success(decrypted):
                envelope = decrypted
            case .terminalDrop:
                // Permanent failure (key missing / tampered): drop the
                // record so the mailbox doesn't keep re-feeding it on
                // every poll.
                await deleteAfterDispatch(id: record.id)
                return
            case .transientLeave:
                // Transient failure (Keychain locked / not yet
                // unlocked). Leave the record in CloudKit and bump
                // `lastSeen` past it so we don't loop on it for the
                // current session — a future agent / app run with an
                // unlocked keychain can still see it.
                if record.createdAt > lastSeen {
                    lastSeen = record.createdAt
                }
                return
            }
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

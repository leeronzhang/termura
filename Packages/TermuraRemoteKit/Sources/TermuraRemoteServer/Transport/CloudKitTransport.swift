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
/// OWNER: caller (typically the host's server assembly)
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
        /// D-3 — after this many consecutive failures we stop polling
        /// entirely (`isCircuitOpen = true`) instead of plateauing at
        /// `backoffCap` forever. Higher than the agent-XPC autoConnector
        /// threshold (8) because CloudKit failures are usually transient
        /// network issues, not configuration mistakes; we'd rather
        /// tolerate longer outages than aggressively halt against a
        /// momentary Wi-Fi drop. Recovery is via `stop()` + `start()`
        /// (toggle off/on in Settings UI) which resets the breaker.
        public let circuitBreakerThreshold: Int

        public init(
            pollInterval: Duration = .seconds(60),
            healthFailureThreshold: Int = 5,
            backoffCap: Duration = .seconds(600),
            circuitBreakerThreshold: Int = 16
        ) {
            self.pollInterval = pollInterval
            self.healthFailureThreshold = healthFailureThreshold
            self.backoffCap = backoffCap
            self.circuitBreakerThreshold = circuitBreakerThreshold
        }
    }

    /// Poll-loop health summary. `unhealthy` flips on after
    /// `healthFailureThreshold` consecutive failures and clears the moment a
    /// poll succeeds; `isCircuitOpen` (D-3) flips after
    /// `circuitBreakerThreshold` failures and stays set until `stop()` /
    /// `start()` resets the actor — at which point the polling loop has
    /// already exited so a stuck CloudKit outage stops draining battery
    /// + cellular data.
    public struct PollHealth: Sendable, Equatable {
        public let isHealthy: Bool
        public let consecutiveFailures: Int
        public let lastFailureReason: String?
        public let isCircuitOpen: Bool

        public init(
            isHealthy: Bool,
            consecutiveFailures: Int,
            lastFailureReason: String? = nil,
            isCircuitOpen: Bool = false
        ) {
            self.isHealthy = isHealthy
            self.consecutiveFailures = consecutiveFailures
            self.lastFailureReason = lastFailureReason
            self.isCircuitOpen = isCircuitOpen
        }

        public static let healthy = PollHealth(isHealthy: true, consecutiveFailures: 0)
    }

    public nonisolated let name: String
    /// Out-of-band failure stream. Surfaced through the `RemoteTransport`
    /// protocol so the host (Mac `RemoteServerHarness` →
    /// `RemoteControlController` → Settings UI) can show *why* a reply
    /// pipeline went silent — without this, `CloudKitReplyChannel.send`
    /// errors only landed in the router's catch-and-log and the user
    /// saw a frozen iPhone with no actionable hint.
    public nonisolated let events: AsyncStream<ServerTransportEvent>
    private let eventsContinuation: AsyncStream<ServerTransportEvent>.Continuation
    /// Module-internal so the same-module `+Polling` extension can pass
    /// `targetDeviceId` straight to the gateway without an extra hop.
    let deviceId: UUID
    /// Module-internal so the same-module `+Polling` / `+Quarantine`
    /// extensions can fetch + delete without widening the public surface.
    let gateway: any CloudKitDatabaseGateway
    /// Module-internal so the same-module `+CipherDecode` extension can
    /// reach the store without widening the public actor surface.
    let pairKeyStore: (any PairKeyStore)?
    /// Module-internal for the same reason as `pairKeyStore` above.
    let codec: any RemoteCodec
    /// Module-internal so the same-module `+Polling` extension can read
    /// the backoff parameters when scheduling the next tick.
    let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var pollingTask: Task<Void, Never>?
    /// Module-internal so the same-module `+Polling` extension can
    /// route poll-fetched records to the active handler. The poll loop
    /// short-circuits when this is nil (e.g. after `stop`).
    var handler: (any EnvelopeHandler)?
    /// Module-internal so the same-module `+Polling` extension can
    /// advance the cursor as it consumes records / quarantines poison.
    var lastSeen: Date = .distantPast
    private var channels: [UUID: CloudKitReplyChannel] = [:]
    /// Module-internal so the same-module `+Polling` extension can
    /// update health bookkeeping without going through public hops.
    var consecutivePollFailures = 0
    var lastPollFailureReason: String?
    /// D-3 — flipped by `+Polling.recordPollFailure` once the
    /// consecutive-failure count crosses
    /// `configuration.circuitBreakerThreshold`. The poll loop checks
    /// this at the top of each iteration and returns early when set,
    /// so a sustained outage stops hammering the gateway entirely
    /// instead of plateauing at `backoffCap` forever. Cleared by
    /// `stop()` so toggle-off-on in Settings UI is the natural
    /// recovery path.
    var isCircuitOpen = false

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
        let made = AsyncStream.makeStream(of: ServerTransportEvent.self)
        events = made.stream
        eventsContinuation = made.continuation
    }

    deinit {
        // Subscribers iterating `for await` fall out of their loop
        // when the actor is released; mirrors `WebSocketClientTransport`'s
        // teardown so consumers do not need to special-case CloudKit.
        eventsContinuation.finish()
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
            lastFailureReason: lastPollFailureReason,
            isCircuitOpen: isCircuitOpen
        )
    }

    public func start(handler: any EnvelopeHandler) async throws {
        guard pollingTask == nil else { throw TransportError.alreadyRunning }
        self.handler = handler
        let initial: CloudKitFetchPage
        do {
            initial = try await gateway.fetch(targetDeviceId: deviceId, since: .distantPast)
        } catch {
            self.handler = nil
            throw TransportError.bindFailure(reason: error.localizedDescription)
        }
        // Consume any backlog the inbox already holds (offline iPhone /
        // server restart) instead of advancing the cursor past it. Each
        // dispatched record gets `delete`d, so subsequent restarts won't
        // see it again; quarantined entries are removed + cursor is
        // advanced past them by the same path the poll loop uses.
        await consume(page: initial, handler: handler)
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
        // D-3 — clean slate so the next `start()` re-arms the breaker
        // from zero. Toggle-off-on in Settings is the user's recovery
        // path after the breaker opens against a sustained outage.
        consecutivePollFailures = 0
        lastPollFailureReason = nil
        isCircuitOpen = false
    }

    /// Triggered by silent push (APNs) — bypasses the poll interval.
    public func ingestPushNotification() async {
        await pollOnce()
    }

    func dispatch(record: CloudKitEnvelopeRecord, handler: any EnvelopeHandler) async {
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

    func deleteAfterDispatch(id: String) async {
        do {
            try await gateway.delete(id: id)
        } catch {
            logger.warning("Failed to delete consumed record \(id): \(error.localizedDescription)")
        }
    }

    private func channelFor(sourceDeviceId: UUID) -> CloudKitReplyChannel {
        if let existing = channels[sourceDeviceId] { return existing }
        // Capture the continuation by value (Sendable) rather than `self`,
        // so the channel actor can yield without re-entering this actor's
        // isolation domain on every send-failure.
        let continuation = eventsContinuation
        let channel = CloudKitReplyChannel(
            transportDeviceId: deviceId,
            peerDeviceId: sourceDeviceId,
            gateway: gateway,
            pairKeyStore: pairKeyStore,
            codec: codec,
            clock: clock,
            eventSink: { event in continuation.yield(event) }
        )
        channels[sourceDeviceId] = channel
        return channel
    }
}

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
/// Wave 1 — poll failures now feed an exponential-backoff schedule + a
/// `pollHealth()` snapshot the iOS UI can surface, so a CloudKit outage
/// stops looking to the user like "the app froze". Cipher decode
/// failures distinguish transient (Keychain locked / first-unlock
/// pending) from permanent (key missing / tampered); transient
/// outcomes leave the record in the mailbox for a future unlocked run.
///
/// OWNER: caller (typically `RemoteStore`)
/// CANCEL: `disconnect()` cancels the poll Task and resumes pending receivers
/// TEARDOWN: drop reference; actor cleanup runs on disconnect
public actor CloudKitClientTransport: ClientTransport {
    // `Configuration` and `PollHealth` value types live in
    // `CloudKitClientTransport+Health.swift` to keep this file under
    // the SwiftLint file_length warning threshold (300).

    nonisolated let codec: any RemoteCodec
    /// Out-of-band failure stream shared with `WebSocketClientTransport`
    /// so the iOS reconnect controller can react to a CloudKit-side
    /// `gateway.save` failure without polling. Pre-fix the iOS user saw
    /// "no reply received" with no signal that the *outbound* write
    /// itself had failed (CKError quota / unauthorized / network drop);
    /// the next `send` would still throw, but until something tried to
    /// send the only place the failure surfaced was the actor-internal
    /// throw → router catch-and-log on the Mac side.
    public nonisolated let events: AsyncStream<TransportEvent>
    private let eventsContinuation: AsyncStream<TransportEvent>.Continuation
    /// Module-internal so the same-module `+Polling` extension can use
    /// it as the fetch target without an extra accessor.
    let localDeviceId: UUID
    private let peerDeviceId: UUID
    /// Module-internal for the same reason as `localDeviceId` above.
    let gateway: any CloudKitDatabaseGateway
    /// Module-internal so the same-module `+CipherDecode` extension can
    /// reach the store without widening the public actor surface.
    let pairKeyStore: (any PairKeyStore)?
    /// Module-internal so the same-module `+Polling` extension can read
    /// the backoff parameters when scheduling the next tick.
    let configuration: Configuration
    private let clock: @Sendable () -> Date
    private var pollingTask: Task<Void, Never>?
    /// Module-internal so the same-module `+Polling` and `+CipherDecode`
    /// extensions can read/update without re-routing through public
    /// surfaces. The actor's isolation domain still serialises access.
    var lastSeen: Date = .distantPast
    private var queue: [Envelope] = []
    private var waiters: [CheckedContinuation<Envelope, any Error>] = []
    var isConnected = false
    var consecutivePollFailures = 0
    var lastPollFailureReason: String?
    /// D-3 — flipped by `+Polling.recordPollFailure` once the
    /// consecutive-failure count crosses
    /// `configuration.circuitBreakerThreshold`. Recovery on iOS is via
    /// `disconnect()` (resets the breaker) followed by the next
    /// reconnect cycle.
    var isCircuitOpen = false
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
        let made = AsyncStream.makeStream(of: TransportEvent.self)
        events = made.stream
        eventsContinuation = made.continuation
    }

    deinit {
        // Mirror `WebSocketClientTransport.deinit`: subscribers iterating
        // `for await` fall out of their loop the moment the transport is
        // released so the iOS reconnect controller never hangs.
        eventsContinuation.finish()
    }

    /// Switches `send` from plaintext-bootstrap mode to encrypted mode.
    /// Called by `RemoteStore` once `PairingCompleteAck.pairingId` lands
    /// and the matching `PairKey` is in `pairKeyStore`. Passing `nil`
    /// reverts to plaintext (e.g. on disconnect).
    public func setActivePairingId(_ id: UUID?) {
        activePairingId = id
    }

    /// Snapshot of the most recent poll outcome. iOS UI / RemoteStore
    /// can read this to surface "CloudKit unreachable" instead of
    /// leaving the user staring at a hung session list.
    public func pollHealth() -> PollHealth {
        PollHealth(
            isHealthy: consecutivePollFailures < configuration.healthFailureThreshold,
            consecutiveFailures: consecutivePollFailures,
            lastFailureReason: lastPollFailureReason,
            isCircuitOpen: isCircuitOpen
        )
    }

    public func connect() async throws {
        guard !isConnected else { return }
        let initial: CloudKitFetchPage
        do {
            initial = try await gateway.fetch(targetDeviceId: localDeviceId, since: .distantPast)
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
        // Drain the offline-backlog before the poll loop starts so
        // messages queued while the iPhone was offline / asleep aren't
        // silently skipped past. Quarantined entries are deleted from
        // CloudKit + the cursor advances past them so they don't loop
        // forever on the next fetch.
        await consume(page: initial)
        pollingTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    public func send(_ envelope: Envelope) async throws {
        guard isConnected else {
            let err = ClientTransportError.notConnected
            yieldDisconnected(reason: err)
            throw err
        }
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
            let err = ClientTransportError.sendFailure(reason: error.localizedDescription)
            yieldDisconnected(reason: err)
            throw err
        }
    }

    /// Mirrors `WebSocketClientTransport.markDeadIfFatal` — a CloudKit
    /// `gateway.save` failure is the moral equivalent of a fatal NWError
    /// on the WebSocket path: the outbound pipe is unusable until the
    /// underlying issue (network / CKError quota / not-authenticated)
    /// resolves. Yielding `.disconnected` lets the iOS reconnect
    /// controller drive recovery uniformly across both transports.
    private func yieldDisconnected(reason: ClientTransportError) {
        eventsContinuation.yield(.disconnected(reason: reason))
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
        // D-3 — clean slate so the next `connect()` re-arms the
        // breaker from zero. The reconnect controller's natural
        // disconnect → reconnect cycle is the recovery path after
        // the breaker opens against a sustained outage.
        consecutivePollFailures = 0
        lastPollFailureReason = nil
        isCircuitOpen = false
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

    func deliver(envelope: Envelope) {
        if waiters.isEmpty {
            queue.append(envelope)
            return
        }
        let waiter = waiters.removeFirst()
        waiter.resume(returning: envelope)
    }
}

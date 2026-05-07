// Wraps the LAN `RemoteServer` from TermuraRemoteKit and adapts it to the public
// `RemoteIntegration` protocol consumed by `AppServices`. Lifecycle is opt-in:
// `start()` is invoked by Settings UI (PR9), never automatically at app launch.
//
// Identity (Ed25519 keypair) and paired-device records are both persisted in the
// macOS Keychain so that restarts preserve pairings — a fresh keypair on every
// launch would invalidate every iPhone the user previously paired.

import CryptoKit
import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteServerHarness")

private enum KeychainServices {
    static let identity = "com.termura.remote.identity"
    static let pairedDevices = "com.termura.remote.paired-devices"
    /// PR7 — symmetric pair-key store. Distinct keychain service so a
    /// future PR9 disable / revoke-all flow can wipe pair keys without
    /// touching the long-lived signing identity.
    static let pairKeys = "com.termura.remote.pair-key.v2"
}

actor RemoteServerHarness: RemoteIntegration {
    private let adapter: any RemoteSessionsAdapter
    private let accountChecker: any ICloudAccountChecker
    private let subscriptionGatewayFactory: @Sendable () -> any CloudKitSubscriptionGateway
    /// Module-internal so same-module extensions (`+Lookup.swift`,
    /// `+Migration.swift`) can lazy-resolve the stack via
    /// `assembleIfNeeded()` without going through a public actor hop.
    var assembled: AssembledStack?
    private(set) var isRunning = false
    // D-1 — host-facing failure stream + drain handle. See
    // `+TransportEvents.swift` for full ownership notes (WHY/OWNER/
    // TEARDOWN/TEST tags live there next to the Task site).
    let transportFailureStream: AsyncStream<RemoteTransportFailure>
    let transportFailureContinuation: AsyncStream<RemoteTransportFailure>.Continuation
    var transportEventDrainTask: Task<Void, Never>?

    // PR8 Phase 2 — agent bridge needs lazy access to the assembled
    // stack so the ingress, virtual reply channel, and trusted-source
    // gate share the same router / pair-key store / paired-device
    // store the LAN/CloudKit transports already use.
    func ensureAssembled() async throws -> AssembledStack {
        try await assembleIfNeeded()
    }

    struct AssembledStack {
        let server: RemoteServer
        let pairingService: PairingService
        let subscriptionGateway: any CloudKitSubscriptionGateway
        let cloudKit: CloudKitTransport?
        let macDeviceId: UUID
        let auditLog: any AuditLogStore
        // PR8 Phase 2 — exposed to `RemoteAgentBridgeAssembly` so the
        // ingress / virtual reply channel reuse the same router state
        // and crypto material the LAN/CloudKit transports already do.
        let router: RemoteEnvelopeRouter
        let pairedDeviceStore: any PairedDeviceStore
        let pairKeyStore: any PairKeyStore
        let gateway: any CloudKitDatabaseGateway
        let codec: any RemoteCodec
    }

    init(
        adapter: any RemoteSessionsAdapter,
        accountChecker: any ICloudAccountChecker = LiveICloudAccountChecker(),
        subscriptionGatewayFactory: @escaping @Sendable () -> any CloudKitSubscriptionGateway = { LiveCloudKitSubscriptionGateway() }
    ) {
        self.adapter = adapter
        self.accountChecker = accountChecker
        self.subscriptionGatewayFactory = subscriptionGatewayFactory
        // WHY: D-1 single failure stream the controller drains across enable/disable.
        // OWNER: RemoteServerHarness; drain Task in +TransportEvents.swift.
        // TEARDOWN: deinit cancels drain + finishes continuation.
        // TEST: Packages/.../CloudKitReplyChannelEventTests.
        let made = AsyncStream.makeStream(of: RemoteTransportFailure.self)
        transportFailureStream = made.stream
        transportFailureContinuation = made.continuation
    }

    deinit {
        // Drain must not outlive actor; continuation.finish() lets the
        // controller `for await` fall through on launcher swap / test reset.
        transportEventDrainTask?.cancel()
        transportFailureContinuation.finish()
    }

    func start() async throws {
        guard !isRunning else { return }
        let stack = try await assembleIfNeeded()
        // iCloud account check + CK subscription only matter when CloudKit
        // is wired in; LAN-only builds receive a Null subscription gateway.
        if stack.cloudKit != nil {
            try await ensureAccountAvailable()
        }
        try await stack.server.start()
        if stack.cloudKit != nil {
            do {
                try await stack.subscriptionGateway.register(targetDeviceId: stack.macDeviceId)
            } catch {
                await stack.server.stop()
                logger.error("Subscription registration failed; rolling back: \(error.localizedDescription)")
                throw error
            }
        }
        // Start the session-list broadcaster so iOS sees opens/closes
        // without polling. Must be after `server.start()` so the channels
        // map can fill as peers pair; before `isRunning = true` so a fast
        // `stop()` reaching us next still tears it down via the symmetric
        // path below.
        await stack.router.startBroadcasting()
        startTransportEventDrain(for: stack)
        isRunning = true
        logger.info("Remote server started (cloudKit=\(stack.cloudKit != nil ? "on" : "off"))")
    }

    func stop() async {
        guard isRunning, let stack = assembled else { return }
        stopTransportEventDrain()
        await stack.router.stopBroadcasting()
        await stack.server.stop()
        if stack.cloudKit != nil {
            do {
                try await stack.subscriptionGateway.unregister(for: stack.macDeviceId)
            } catch {
                logger.warning("Subscription unregister failed: \(error.localizedDescription)")
            }
        }
        isRunning = false
        logger.info("Remote server stopped")
    }

    private func ensureAccountAvailable() async throws {
        let status = try await accountChecker.currentStatus()
        guard status == .available else {
            logger.error("iCloud account not available: \(status.rawValue)")
            throw RemoteHarnessError.iCloudUnavailable(status: status)
        }
    }

    /// Lazy assembly so that `RemoteIntegrationFactory.make` can stay synchronous
    /// (called from `AppDelegate.init` which can't be `async throws`). Keychain
    /// I/O happens on the first `start()` or `issueInvitation()`. Module-
    /// internal so same-module `+Lookup.swift` and `+Migration.swift` can
    /// share the lazy-resolve pattern without re-deriving a separate path.
    func assembleIfNeeded() async throws -> AssembledStack {
        if let assembled { return assembled }
        let codec = JSONRemoteCodec()
        let identityStore = KeychainDeviceIdentityStore(serviceName: KeychainServices.identity)
        let identity = try await identityStore.loadOrCreate()
        let pairingStore = KeychainPairedDeviceStore(serviceName: KeychainServices.pairedDevices)
        // PR8 — back-fill `cloudSourceDeviceId` on legacy entries; see
        // `+Migration.swift` for rationale and failure semantics.
        await Self.backfillCloudSourceIds(for: pairingStore)
        let pairKeyStore = KeychainPairKeyStore(serviceName: KeychainServices.pairKeys)
        let pairing = Self.makePairingService(
            identity: identity,
            store: pairingStore,
            pairKeyStore: pairKeyStore
        )
        let policy = DangerousCommandPolicy()
        let snapshotPublisher = try await Self.makeSnapshotPublisher()
        let auditStore: any AuditLogStore = FileAuditLogStore(fileURL: Self.auditLogURL())
        let activatorBox = Self.makeActivatorWiring()
        let router = RemoteEnvelopeRouter(
            adapter: adapter,
            pairingService: pairing,
            policy: policy,
            snapshotPublisher: snapshotPublisher,
            codec: codec,
            auditLog: auditStore,
            cloudKitChannelActivator: activatorBox
        )
        let lan = LANTransport(name: Self.bonjourName(), codec: codec)
        let macDeviceId = Self.deriveDeviceId(from: identity.publicKeyData)

        // CloudKit transport is enabled by default. Set
        // `TERMURA_REMOTE_DISABLE_CLOUDKIT=1` in the scheme env to fall
        // back to LAN-only (e.g. when iterating on a developer team
        // whose `iCloud.com.termura.remote` container isn't provisioned
        // yet — `CKContainer(identifier:)` traps hard in that case and
        // the kill-switch keeps the rest of the harness running).
        let cloudKitWiring = await Self.makeCloudKitWiring(
            macDeviceId: macDeviceId,
            pairKeyStore: pairKeyStore,
            codec: codec,
            activatorBox: activatorBox
        )
        let stack = Self.makeStack(StackInputs(
            router: router,
            pairing: pairing,
            pairingStore: pairingStore,
            pairKeyStore: pairKeyStore,
            lan: lan,
            cloudKitWiring: cloudKitWiring,
            subscriptionGateway: Self.makeSubscriptionGateway(cloudKitWiring: cloudKitWiring, liveFactory: subscriptionGatewayFactory),
            macDeviceId: macDeviceId,
            auditStore: auditStore,
            codec: codec
        ))
        assembled = stack
        return stack
    }

    static func bonjourName() -> String {
        let raw = ProcessInfo.processInfo.hostName
        return raw.isEmpty ? "termura-mac" : raw
    }

    private static func auditLogURL() -> URL {
        termuraSupportDirectory().appendingPathComponent("remote-audit.json")
    }

    static func attachmentsRootURL() -> URL {
        termuraSupportDirectory().appendingPathComponent("RemoteAttachments", isDirectory: true)
    }

    static func termuraSupportDirectory() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Termura", isDirectory: true)
    }

    /// Derives a stable per-Mac UUID from the persisted Ed25519 public key so
    /// the same device id surfaces on every launch. Stable id is required for
    /// the CloudKit transport's `targetDeviceId` cursor — a fresh UUID per
    /// launch would orphan in-flight envelopes addressed to the previous id.
    private static func deriveDeviceId(from publicKey: Data) -> UUID {
        let digest = SHA256.hash(data: publicKey)
        var bytes = Array(digest.prefix(16))
        // Mark as RFC 4122 v5 (name-based, SHA-1 hashed) to keep the id valid
        // even though we use SHA-256 — the version/variant bits are what
        // matter for UUID consumers.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

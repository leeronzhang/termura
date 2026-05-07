// PR8 §3.7 — one-shot migration helpers run during harness assembly.
// Lives in its own file so the migration code (and its rationale
// comments) doesn't bloat the main `RemoteServerHarness` file, which
// is at the SwiftLint `file_length` budget. CLAUDE.md §10: new
// changes must not expand legacy debt.

import Foundation
import OSLog
import TermuraRemoteProtocol
import TermuraRemoteServer

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteServerHarness+Migration")

// CloudKit transport wiring carved out of `assembleIfNeeded` so the
// main `RemoteServerHarness.swift` stays under SwiftLint's
// `function_body_length` and `file_length` budgets.
struct CloudKitWiring: Sendable {
    let transport: CloudKitTransport?
    let gateway: any CloudKitDatabaseGateway
}

extension RemoteServerHarness {
    /// Bundle of parameters threaded through `makeStack` — kept here
    /// so the helper signature stays inside SwiftLint's
    /// `function_parameter_count` budget while the assembly path
    /// keeps using named field semantics for readability.
    struct StackInputs: Sendable {
        let router: RemoteEnvelopeRouter
        let pairing: PairingService
        let pairingStore: KeychainPairedDeviceStore
        let pairKeyStore: KeychainPairKeyStore
        let lan: LANTransport
        let cloudKitWiring: CloudKitWiring
        let subscriptionGateway: any CloudKitSubscriptionGateway
        let macDeviceId: UUID
        let auditStore: any AuditLogStore
        let codec: any RemoteCodec
    }

    /// Final composition of the assembled stack — pulled out so the
    /// `assembleIfNeeded` body stays under the SwiftLint
    /// `function_body_length` budget.
    static func makeStack(_ inputs: StackInputs) -> RemoteServerHarness.AssembledStack {
        let server = RemoteServer(
            transports: inputs.cloudKitWiring.transport.map { [inputs.lan, $0] } ?? [inputs.lan],
            handler: inputs.router
        )
        return RemoteServerHarness.AssembledStack(
            server: server,
            pairingService: inputs.pairing,
            subscriptionGateway: inputs.subscriptionGateway,
            cloudKit: inputs.cloudKitWiring.transport,
            macDeviceId: inputs.macDeviceId,
            auditLog: inputs.auditStore,
            router: inputs.router,
            pairedDeviceStore: inputs.pairingStore,
            pairKeyStore: inputs.pairKeyStore,
            gateway: inputs.cloudKitWiring.gateway,
            codec: inputs.codec
        )
    }

    /// Constructs the `PairingService` used by `assembleIfNeeded`.
    /// Extracted to keep the assembly function below SwiftLint's
    /// `function_body_length` budget while preserving identity /
    /// pair-key wiring symmetry with PR7.
    static func makePairingService(
        identity: DeviceIdentity,
        store: KeychainPairedDeviceStore,
        pairKeyStore: KeychainPairKeyStore
    ) -> PairingService {
        let issuer = PairingTokenIssuer(lifetime: 300)
        return PairingService(
            identity: identity,
            tokenIssuer: issuer,
            store: store,
            serviceName: bonjourName(),
            pairKeyStore: pairKeyStore
        )
    }

    /// PR6 close-out: persists oversized snapshots to a local-file
    /// attachment store. Bootstrap failures abort harness assembly
    /// because there is no usable degraded mode (every >256KB
    /// output would otherwise collapse silently).
    static func makeSnapshotPublisher() async throws -> SnapshotPublisher {
        let attachmentStore = LocalFileAttachmentStore(rootURL: Self.attachmentsRootURL())
        do {
            try await attachmentStore.bootstrap()
        } catch {
            logger.error("Attachment store bootstrap failed; aborting harness assembly: \(error.localizedDescription)")
            throw error
        }
        return SnapshotPublisher(attachmentStore: attachmentStore)
    }

    /// PR7 — router needs a callback into the CloudKit transport so
    /// it can flip the per-peer reply channel from plaintext-
    /// bootstrap to encrypted mode after a pair / rejoin handshake.
    /// The harness owns the wiring so the router doesn't have to know
    /// about transports at all. Wave 5 — returns the box itself (which
    /// conforms to `CloudKitChannelActivator`) instead of bridging
    /// through a closure shim.
    static func makeActivatorWiring() -> CloudKitActivatorBox {
        CloudKitActivatorBox()
    }

    /// Builds the live CloudKit transport by default; returns the LAN-only
    /// stub only when `TERMURA_REMOTE_DISABLE_CLOUDKIT=1` is set.
    ///
    /// History: prior to this gate-flip Mac required an opt-in
    /// `TERMURA_REMOTE_ENABLE_CLOUDKIT=1` env var that wasn't set in any
    /// scheme/yml/xcconfig, so cross-network pairing silently failed —
    /// iOS wrote pairInit to CloudKit while Mac ran LAN-only with a
    /// `NullCloudKitSubscriptionGateway`, leaving the iOS pairing UI
    /// hanging forever. The opt-in was a pre-PR8 dev-period guard
    /// against `CKContainer(identifier:)` trapping on un-provisioned
    /// iCloud containers; both bundle entitlements now declare
    /// `iCloud.com.termura.remote`, and iOS already runs CloudKit
    /// without any gate, so the container is provably provisioned and
    /// the guard is obsolete.
    ///
    /// Escape hatch: the kill-switch is preserved (re-named to
    /// `TERMURA_REMOTE_DISABLE_CLOUDKIT=1`) so a developer hitting an
    /// unexpected entitlement / provisioning regression can fall back
    /// to LAN-only without code changes.
    static func makeCloudKitWiring(
        macDeviceId: UUID,
        pairKeyStore: any PairKeyStore,
        codec: any RemoteCodec,
        activatorBox: CloudKitActivatorBox
    ) async -> CloudKitWiring {
        guard cloudKitEnabledForEnvironment(ProcessInfo.processInfo.environment) else {
            logger.notice("CloudKit transport disabled (TERMURA_REMOTE_DISABLE_CLOUDKIT=1); LAN only")
            return CloudKitWiring(transport: nil, gateway: NullCloudKitDatabaseGateway())
        }
        let liveGateway = LiveCloudKitDatabaseGateway()
        let transport = CloudKitTransport(
            name: "cloudkit",
            deviceId: macDeviceId,
            gateway: liveGateway,
            pairKeyStore: pairKeyStore,
            codec: codec,
            configuration: macCloudKitTransportConfiguration()
        )
        await activatorBox.bind(transport: transport)
        return CloudKitWiring(transport: transport, gateway: liveGateway)
    }

    /// Mac-side CloudKitTransport tuning. The package-level default is
    /// `pollInterval: 60s`, calibrated for an iOS peer that gets silent
    /// push wake-ups and uses poll only as a safety net. Mac is a
    /// different story:
    ///
    /// 1. macOS direct-distribution apps need an explicit
    ///    `aps-environment` entitlement (now declared) AND a
    ///    provisioning profile authorizing it to actually receive APNs.
    ///    Even with the entitlement, CKContainer's silent-push path
    ///    can be blocked by an iCloud account refresh, an APNs token
    ///    not-yet-registered window, or a push subscription that
    ///    server-side fires but never reaches the client. In those
    ///    states the only delivery mechanism is poll.
    /// 2. Mac is the receiving end of cross-network pair / rejoin /
    ///    every iOS-originated business envelope. A 60s default makes
    ///    pair handshake take 60-120s in the field — observed in user
    ///    sessions today (16:12 → 16:13 example).
    /// 3. CloudKit's free tier is 40 req/sec/user. 5s polling is
    ///    0.2 req/sec — three orders of magnitude under the limit.
    ///    Battery cost is negligible: each fetch is < 1KB and Mac
    ///    is plugged in / on AC most of the time.
    ///
    /// We keep the public default (60s) untouched so iOS still gets
    /// the long-poll-with-push semantics; only the Mac harness
    /// instantiation overrides. Tests pin this constant so a future
    /// regression to the package default surfaces immediately.
    static let macPollInterval: Duration = .seconds(5)

    static func macCloudKitTransportConfiguration() -> CloudKitTransport.Configuration {
        CloudKitTransport.Configuration(pollInterval: macPollInterval)
    }

    /// Pure decision function carved out of `makeCloudKitWiring` so unit
    /// tests can pin the gate semantics (default-on, opt-out via env)
    /// without standing up `CKContainer`. Returns `true` for the default
    /// "no env override" case and for any value other than the literal
    /// `"1"` — keeping the kill-switch strict so a future typo
    /// (`DISABLE_CLOUDKIT=true`, `=yes`) can't silently disable
    /// CloudKit.
    static func cloudKitEnabledForEnvironment(_ environment: [String: String]) -> Bool {
        environment["TERMURA_REMOTE_DISABLE_CLOUDKIT"] != "1"
    }

    /// Subscription-gateway construction must follow CloudKit gating:
    /// `LiveCloudKitSubscriptionGateway.init` calls
    /// `CKContainer(identifier:)`, which traps hard when the
    /// `com.apple.developer.icloud-services` entitlement is missing —
    /// not a Swift error, a `Significant issue` abort that can't be
    /// caught. LAN-only builds therefore receive a Null stand-in;
    /// `start` / `stop` already guard on `stack.cloudKit != nil`
    /// before invoking subscription methods, so the Null impl is
    /// reached only on programming errors.
    static func makeSubscriptionGateway(
        cloudKitWiring: CloudKitWiring,
        liveFactory: () -> any CloudKitSubscriptionGateway
    ) -> any CloudKitSubscriptionGateway {
        cloudKitWiring.transport != nil ? liveFactory() : NullCloudKitSubscriptionGateway()
    }

    /// Fills in `cloudSourceDeviceId` on every legacy `PairedDevice`
    /// whose persisted entry pre-dates PR8 so the trusted-source gate
    /// can do an O(1) reverse lookup instead of re-hashing each
    /// `publicKey` on every CloudKit ingest.
    ///
    /// Failure is non-fatal: each gate lookup still has the public-key
    /// fallback path, the only cost is a one-time SHA-256 per legacy
    /// entry. Aborting harness assembly over a transient keychain
    /// hiccup here would also block fresh pair flows that would
    /// otherwise succeed, so we log and continue.
    static func backfillCloudSourceIds(for store: KeychainPairedDeviceStore) async {
        do {
            try await store.backfillCloudSourceDeviceIdIfMissing(
                deriving: DeviceIdentity.deriveDeviceId(from:)
            )
        } catch {
            logger.warning(
                "Backfill of cloudSourceDeviceId failed; legacy entries will fall back to runtime derivation: \(error.localizedDescription)"
            )
        }
    }
}

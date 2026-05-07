// PR8 Phase 2 §7 — three-step completion state machine. Owns the
// inbound XPC connection (set by `AgentXPCService` via `bind`),
// `gateway.delete`, cursor advancement, and quarantine upgrades.
// Returns a `ConsumeOutcome` so the runner can decide whether to
// continue, halt this poll, or skip to the next record.
//
// Stop policy: a Step 1 deliver mid-call is cancelled; a Step 2
// `gateway.delete` mid-call is allowed to run to completion so we
// never end up "deliver succeeded but delete unsent" (would lose
// messages by deleting cursor advance ground truth).

import Foundation
import OSLog
@preconcurrency import TermuraAgentXPCInterfaces
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentAppDispatcher")

enum ConsumeOutcome: Sendable, Equatable {
    case advanced(to: Date)
    case blocked(reason: String)
    case quarantined(recordName: String, reason: String)
}

actor AgentAppDispatcher {
    /// Reasons that should never be counted as a "real" attempt — the
    /// failure is link-level (XPC connection torn down, ingress
    /// shutting down) and counting them would let normal noise
    /// promote a record to quarantine.
    static let nonAttemptReasonCodes: Set<String> = [
        "shutdown",
        "connection_invalidated",
        "agent_unavailable"
    ]

    /// Reasons that warrant quarantine upgrade after N attempts.
    /// `cipher_open_failed` is excluded because the cipher path
    /// already returns terminal `success=true` from the ingress, so
    /// it's never visible as a retry path here.
    static let attemptCountedReasonCodes: Set<String> = [
        "decode_failed",
        "kind_mismatch",
        "schema_mismatch",
        "pairkey_missing",
        "internal_error",
        "timeout",
        "delete_failed"
    ]

    private let attemptThreshold: Int
    private let cursorStore: AgentCursorStore
    private let quarantineStore: AgentQuarantineStore
    private let gateway: any CloudKitDatabaseGateway
    private let clock: @Sendable () -> Date
    private var connectionHolder: ConnectionHolder?
    private var isStopped = false

    init(
        cursorStore: AgentCursorStore,
        quarantineStore: AgentQuarantineStore,
        gateway: any CloudKitDatabaseGateway,
        attemptThreshold: Int = 5,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.cursorStore = cursorStore
        self.quarantineStore = quarantineStore
        self.gateway = gateway
        self.attemptThreshold = attemptThreshold
        self.clock = clock
    }

    /// Sets the live inbound NSXPCConnection. Called by
    /// `AgentXPCService` whenever it accepts a new connection. The
    /// dispatcher uses `connection.remoteObjectProxy as
    /// AppMailboxProtocol` to push items back to the main app.
    func bind(connection: ConnectionHolder?) {
        connectionHolder = connection
    }

    /// True iff the dispatcher currently holds a live XPC connection to
    /// the main app. Wave 1 — the runner consults this before pulling
    /// any CloudKit batch so we don't burn a fetch every 60 s while the
    /// app is closed (every record would just bounce off `.blocked`
    /// agent_unavailable, advance nothing, and waste CK quota).
    func isAppConnected() -> Bool {
        !isStopped && connectionHolder != nil
    }

    func stop() {
        isStopped = true
        connectionHolder = nil
    }

    /// Single completion entry-point. Implements the three-step
    /// state machine from §7 / data-flow §5.
    func consume(item: AgentMailboxItem) async -> ConsumeOutcome {
        if isStopped {
            return .blocked(reason: "shutdown")
        }
        guard let holder = connectionHolder else {
            return .blocked(reason: "agent_unavailable")
        }
        // Step 1 — deliver via reverse XPC.
        let reply = await holder.deliver(item: item)
        if !reply.success {
            return await handleRetryableFailure(item: item, reasonCode: reply.reasonCode)
        }
        // Step 2 — delete CK record.
        do {
            try await gateway.delete(id: item.recordName)
        } catch {
            logger.warning("delete failed for \(item.recordName, privacy: .public): \(error.localizedDescription)")
            return await handleRetryableFailure(item: item, reasonCode: "delete_failed")
        }
        // Step 3 — advance cursor by createdAt.
        do {
            try await cursorStore.advance(to: item.createdAt)
        } catch {
            logger.error("cursor advance failed for \(item.recordName, privacy: .public): \(error.localizedDescription)")
            // Record is already deleted from CloudKit, so future polls
            // can never re-fetch it. Cursor lag is self-healing on
            // next successful advance. Surface as advanced so the
            // runner continues processing the rest.
        }
        return .advanced(to: item.createdAt)
    }

    private func handleRetryableFailure(
        item: AgentMailboxItem,
        reasonCode: String
    ) async -> ConsumeOutcome {
        if Self.nonAttemptReasonCodes.contains(reasonCode) {
            return .blocked(reason: reasonCode)
        }
        guard Self.attemptCountedReasonCodes.contains(reasonCode) else {
            return .blocked(reason: reasonCode)
        }
        let attempts: Int
        do {
            attempts = try await quarantineStore.recordAttempt(
                recordName: item.recordName,
                createdAt: item.createdAt,
                reasonCode: reasonCode,
                now: clock()
            )
        } catch {
            logger.error("quarantine attempt-record failed: \(error.localizedDescription)")
            return .blocked(reason: reasonCode)
        }
        if attempts >= attemptThreshold {
            do {
                // Promote `.retrying` → `.quarantined` so the runner
                // filter starts excluding this record on the next
                // poll. Force cursor past it so subsequent records
                // aren't blocked by this stuck one.
                try await quarantineStore.add(QuarantineEntry(
                    recordName: item.recordName,
                    createdAt: item.createdAt,
                    reasonCode: reasonCode,
                    attempts: attempts,
                    firstSeenAt: clock(),
                    state: .quarantined
                ))
            } catch {
                logger.error("quarantine promotion failed: \(error.localizedDescription)")
            }
            do {
                try await cursorStore.advance(to: item.createdAt)
            } catch {
                logger.error("cursor advance during quarantine upgrade failed: \(error.localizedDescription)")
            }
            return .quarantined(recordName: item.recordName, reason: reasonCode)
        }
        return .blocked(reason: reasonCode)
    }
}

/// Sendable wrapper around the inbound NSXPCConnection's remote
/// proxy. `AgentXPCService` builds it on accept and hands it to the
/// dispatcher; teardown nils it out.
struct ConnectionHolder: Sendable {
    private let proxy: @Sendable (XPCMailboxItem, @escaping @Sendable (Bool, String) -> Void) -> Void

    init(proxy: @escaping @Sendable (XPCMailboxItem, @escaping @Sendable (Bool, String) -> Void) -> Void) {
        self.proxy = proxy
    }

    func deliver(item: AgentMailboxItem) async -> AppMailboxReplyValues {
        let xpc = XPCMailboxItem(
            recordName: item.recordName,
            createdAt: item.createdAt,
            sourceDeviceID: item.sourceDeviceId,
            payloadKind: item.payloadKind.rawValue,
            payloadData: item.payloadData,
            schemaVersion: item.schemaVersion
        )
        return await withCheckedContinuation { (cont: CheckedContinuation<AppMailboxReplyValues, Never>) in
            proxy(xpc) { success, reason in
                cont.resume(returning: AppMailboxReplyValues(success: success, reasonCode: reason))
            }
        }
    }
}

struct AppMailboxReplyValues: Sendable, Equatable {
    let success: Bool
    let reasonCode: String
}

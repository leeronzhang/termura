// PR8 Phase 2 §7.1 — drives the poll loop. Per pollOnce:
// 1. read cursor (Date)
// 2. fetch records since cursor
// 3. sort by createdAt asc
// 4. filter out quarantined recordNames
// 5. iterate serially through dispatcher.consume; halt on the first
//    `.blocked` outcome (preserves cursor for the next round)
//
// Runner does NOT call gateway.delete and does NOT advance cursor —
// the dispatcher owns those side-effects (single source of truth).

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote-agent", category: "AgentCloudKitRunner")

actor AgentCloudKitRunner {
    private let macDeviceId: UUID
    private let gateway: any CloudKitDatabaseGateway
    private let cursorStore: AgentCursorStore
    private let quarantineStore: AgentQuarantineStore
    private let dispatcher: AgentAppDispatcher
    private let pollInterval: Duration
    private var loopTask: Task<Void, Never>?

    init(
        macDeviceId: UUID,
        gateway: any CloudKitDatabaseGateway,
        cursorStore: AgentCursorStore,
        quarantineStore: AgentQuarantineStore,
        dispatcher: AgentAppDispatcher,
        pollInterval: Duration = .seconds(60)
    ) {
        self.macDeviceId = macDeviceId
        self.gateway = gateway
        self.cursorStore = cursorStore
        self.quarantineStore = quarantineStore
        self.dispatcher = dispatcher
        self.pollInterval = pollInterval
    }

    func start() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func stop() async {
        loopTask?.cancel()
        if let task = loopTask {
            await task.value
        }
        loopTask = nil
    }

    /// Single poll cycle. Public so the silent-push delegate can
    /// invoke it directly without waiting for the next interval tick.
    func pollOnce() async {
        // Pre-fix the loop short-circuited before any fetch when the
        // dispatcher had no XPC connection to the main app, on the
        // theory that every record would come back `.blocked` anyway.
        // In practice that guard turned into a hard regression: when
        // the user toggled Settings → Remote Control off and back on,
        // launchd respawned the daemon, but the Mac app's
        // RemoteAgentXPCClient did not always re-establish the
        // NSXPCConnection to the new daemon. The new daemon then
        // observed `isAppConnected == false` forever, skipped every
        // poll, and the cross-network reconnect path went silent —
        // iPhone wrote rejoin envelopes into iCloud, no one polled
        // them, ReconnectView spun forever. The dispatcher's `consume`
        // path already returns `.blocked("agent_unavailable")` on
        // each record when no XPC peer is bound, which halts the
        // per-record loop after the first item — that bounds the
        // wasted work without making the poll itself a no-op. CK
        // free-tier quota at 1 fetch/min is ~0.2 req/s, three orders
        // of magnitude under the limit, so the previous "save the
        // fetch" optimisation is paying nothing back.
        let cursor = await cursorStore.read()
        let page: CloudKitFetchPage
        do {
            page = try await gateway.fetch(targetDeviceId: macDeviceId, since: cursor)
        } catch {
            logger.warning("fetch failed: \(error.localizedDescription)")
            return
        }
        await dropPoisonRecords(page.quarantined)
        let sorted = page.records.sorted { $0.createdAt < $1.createdAt }
        for record in sorted {
            if Task.isCancelled { return }
            if await quarantineStore.contains(recordName: record.id) {
                continue
            }
            let item: AgentMailboxItem
            do {
                item = try makeItem(from: record)
            } catch {
                logger.error("payload encode failed for \(record.id, privacy: .public): \(error.localizedDescription)")
                continue
            }
            let outcome = await dispatcher.consume(item: item)
            switch outcome {
            case .advanced:
                continue
            case let .blocked(reason):
                logger.info("poll halted at \(record.id, privacy: .public): \(reason, privacy: .public)")
                return
            case let .quarantined(recordName, reason):
                logger.error("quarantined \(recordName, privacy: .public): \(reason, privacy: .public)")
                continue
            }
        }
    }

    /// Per-record CloudKit isolation cleanup. The gateway has already
    /// isolated legacy-schema / malformed records into `quarantined`
    /// so they don't poison the batch; here we delete the CK entries
    /// + advance the cursor past their createdAt so subsequent polls
    /// see fresh records. The dispatcher's quarantine store stays the
    /// source of truth for app-side `.quarantined` outcomes
    /// (post-dispatch); these entries never reach dispatch.
    private func dropPoisonRecords(_ quarantined: [QuarantinedRecord]) async {
        for entry in quarantined {
            logger.warning(
                "deleting poison record \(entry.id, privacy: .public): \(entry.reason, privacy: .public)"
            )
            do {
                try await gateway.delete(id: entry.id)
            } catch {
                logger.warning("poison delete failed for \(entry.id, privacy: .public): \(error.localizedDescription)")
            }
            guard let createdAt = entry.createdAt else { continue }
            do {
                try await cursorStore.advance(to: createdAt)
            } catch {
                logger.warning("cursor advance past \(entry.id, privacy: .public) failed: \(error.localizedDescription)")
            }
        }
    }

    private func loop() async {
        while !Task.isCancelled {
            await pollOnce()
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                return
            }
        }
    }

    private func makeItem(from record: CloudKitEnvelopeRecord) throws -> AgentMailboxItem {
        let kind: AgentMailboxItem.PayloadKind
        let data: Data
        switch record.payload {
        case let .plaintext(envelope):
            kind = .plaintext
            data = try JSONEncoder().encode(envelope)
        case let .cipher(blob):
            kind = .cipher
            data = try JSONEncoder().encode(blob)
        }
        return AgentMailboxItem(
            recordName: record.id,
            createdAt: record.createdAt,
            sourceDeviceId: record.sourceDeviceId,
            payloadKind: kind,
            payloadData: data
        )
    }
}

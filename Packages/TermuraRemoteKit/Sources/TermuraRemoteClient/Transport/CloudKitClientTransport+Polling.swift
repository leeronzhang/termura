import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitClientTransport+Polling")

// Poll loop + health bookkeeping in their own file so the main
// `CloudKitClientTransport` stays under the file_length budget. The
// actor's stored properties (`gateway`, `localDeviceId`, `lastSeen`,
// `consecutivePollFailures`, `lastPollFailureReason`, `configuration`,
// `isConnected`) are package-internal so this same-module extension
// can drive the schedule + dispatch without going through public
// hops. Mirrors the server `CloudKitTransport` polling shape so both
// sides degrade identically when CloudKit goes unhealthy.

extension CloudKitClientTransport {
    func runPollLoop() async {
        while !Task.isCancelled {
            _ = await pollOnce()
            do {
                try await Task.sleep(for: nextPollDelay())
            } catch {
                return
            }
        }
    }

    /// Mirrors `CloudKitTransport.nextPollDelay` so the iOS side honours
    /// the same exponential backoff after consecutive failures.
    func nextPollDelay() -> Duration {
        guard consecutivePollFailures > 0 else { return configuration.pollInterval }
        let baseSeconds = Self.durationInSeconds(configuration.pollInterval)
        let multiplier = pow(2.0, Double(min(consecutivePollFailures - 1, 16)))
        let candidateSeconds = baseSeconds * multiplier
        let capSeconds = Self.durationInSeconds(configuration.backoffCap)
        return .seconds(min(candidateSeconds, capSeconds))
    }

    static func durationInSeconds(_ duration: Duration) -> Double {
        let comp = duration.components
        return Double(comp.seconds) + Double(comp.attoseconds) / 1.0e18
    }

    @discardableResult
    func pollOnce() async -> Bool {
        guard isConnected else { return false }
        let page: CloudKitFetchPage
        do {
            page = try await gateway.fetch(targetDeviceId: localDeviceId, since: lastSeen)
        } catch {
            recordPollFailure(reason: error.localizedDescription)
            return false
        }
        await consume(page: page)
        recordPollSuccess()
        return true
    }

    /// Shared consumption path for both `connect`'s initial backlog
    /// drain and the poll loop. Quarantined entries are deleted +
    /// cursor advances past them so a poison record can't keep
    /// blocking later legitimate ones.
    func consume(page: CloudKitFetchPage) async {
        for record in page.records {
            await processFetchedRecord(record)
        }
        for entry in page.quarantined {
            await handleQuarantined(entry)
        }
    }

    private func handleQuarantined(_ entry: QuarantinedRecord) async {
        logger.warning(
            "Quarantining unparseable record \(entry.id, privacy: .public): \(entry.reason, privacy: .public)"
        )
        if let createdAt = entry.createdAt, createdAt > lastSeen {
            lastSeen = createdAt
        }
        do {
            try await gateway.delete(id: entry.id)
        } catch {
            logger.warning(
                "Failed to delete quarantined record \(entry.id): \(error.localizedDescription)"
            )
        }
    }

    /// Routes one fetched record through the cipher / plaintext switch
    /// + delete bookkeeping. Pulled out of `pollOnce` so the body stays
    /// inside the function-length budget while the cipher branch grows
    /// the transient-leave / terminal-drop split.
    private func processFetchedRecord(_ record: CloudKitEnvelopeRecord) async {
        switch record.payload {
        case let .plaintext(envelope):
            deliver(envelope: envelope)
        case let .cipher(blob):
            switch await openCipher(blob) {
            case let .success(envelope):
                deliver(envelope: envelope)
            case .terminalDrop:
                // Permanent failure — fall through to delete so the
                // mailbox doesn't keep re-feeding the same failure.
                break
            case .transientLeave:
                // Transient (Keychain locked); leave in CK and skip the
                // delete so a future agent / app run with an unlocked
                // keychain can decrypt it.
                if record.createdAt > lastSeen {
                    lastSeen = record.createdAt
                }
                return
            }
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

    func recordPollSuccess() {
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

    func recordPollFailure(reason: String) {
        consecutivePollFailures += 1
        lastPollFailureReason = reason
        let failures = consecutivePollFailures
        if failures >= configuration.healthFailureThreshold {
            logger.error("Poll failed (#\(failures)): \(reason, privacy: .public)")
        } else {
            logger.warning("Poll failed (#\(failures)): \(reason, privacy: .public)")
        }
    }
}

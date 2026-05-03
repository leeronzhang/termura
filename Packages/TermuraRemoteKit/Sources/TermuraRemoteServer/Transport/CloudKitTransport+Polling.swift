import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "CloudKitTransport+Polling")

// Poll loop + health bookkeeping + backlog/quarantine handling in their
// own file so the main `CloudKitTransport` stays under the file_length
// budget. The actor's stored properties (`gateway`, `deviceId`,
// `configuration`, `lastSeen`, `consecutivePollFailures`,
// `lastPollFailureReason`) are package-internal so this same-module
// extension can drive the schedule + dispatch without going through
// public hops. Mirrors the iOS-side `CloudKitClientTransport+Polling`
// shape so both sides degrade identically when CloudKit goes
// unhealthy.

extension CloudKitTransport {
    func runPollLoop() async {
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

    func pollOnce() async {
        guard let handler else { return }
        let page: CloudKitFetchPage
        do {
            page = try await gateway.fetch(targetDeviceId: deviceId, since: lastSeen)
        } catch {
            recordPollFailure(reason: error.localizedDescription)
            return
        }
        await consume(page: page, handler: handler)
        recordPollSuccess()
    }

    /// Shared backlog/poll consumption path. `start` calls this once on
    /// the initial inbox so offline-queued messages don't get skipped;
    /// `pollOnce` calls it on every tick. Quarantined entries (poison
    /// records the gateway couldn't parse) are deleted + the cursor
    /// advances past their `createdAt` so the next fetch genuinely sees
    /// fresh records.
    func consume(page: CloudKitFetchPage, handler: any EnvelopeHandler) async {
        for record in page.records {
            await dispatch(record: record, handler: handler)
            if record.createdAt > lastSeen {
                lastSeen = record.createdAt
            }
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

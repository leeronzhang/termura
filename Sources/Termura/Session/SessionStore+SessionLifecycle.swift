import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

// MARK: - Session lifecycle

extension SessionStore {

    @discardableResult
    func createSession(title: String? = nil, shell: String? = nil) -> SessionRecord {
        let resolvedShell = shell ?? defaultShell
        let resolvedTitle = title ?? defaultSessionTitle()
        let record = SessionRecord(
            title: resolvedTitle,
            workingDirectory: projectRoot,
            orderIndex: sessions.count
        )
        appendSession(record)
        engineStore.createEngine(for: record.id, shell: resolvedShell, currentDirectory: projectRoot)
        activeSessionID = record.id
        persistTracked { try await $0.save(record) }
        logger.info("Created session \(record.id) title=\(resolvedTitle)")
        if let collector = metricsCollector {
            let activeCount = sessions.count
            Task { await collector.incrementAndSetGauge(.sessionCreated, gauge: .activeSessions, value: Double(activeCount)) }
        }
        return record
    }

    func endSession(id: SessionID) async {
        guard let preIdx = sessionIndex[id], !sessions[preIdx].isEnded else { return }
        engineStore.terminateEngine(for: id)
        let endDate = clock.now()
        // DB write first — mirrors deleteSession and reopenSession. Prevents the in-memory
        // view showing the session as ended when the DB still considers it active (e.g. on
        // next launch). Memory is mutated only after the DB confirms success.
        do {
            try await repository.markEnded(id: id, at: endDate)
        } catch {
            errorMessage = "Failed to end session: \(error.localizedDescription)"
            logger.error("DB markEnded failed for session \(id): \(error)")
            return
        }
        // Re-check after the await — a concurrent operation may have already removed it.
        guard sessionIndex[id] != nil else { return }
        mutateSession(id: id) { $0.endedAt = endDate }
        // Switch to the most recently active non-ended session if this was focused.
        if activeSessionID == id {
            activeSessionID = sessions.last(where: { !$0.isEnded })?.id
        }
        logger.info("Ended session \(id)")
    }

    func reopenSession(id: SessionID) async {
        guard let idx = sessionIndex[id], sessions[idx].isEnded else { return }
        do {
            try await repository.markReopened(id: id)
        } catch {
            errorMessage = "Failed to reopen session: \(error.localizedDescription)"
            logger.error("DB markReopened failed for session \(id): \(error)")
            return
        }
        mutateSession(id: id) { $0.endedAt = nil }
        activateSession(id: id)
        logger.info("Reopened session \(id)")
    }

}

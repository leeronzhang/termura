import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionStore")

// MARK: - Session lifecycle

extension SessionStore {
    @discardableResult
    func createSession(title: String? = nil, shell: String? = nil) -> SessionRecord {
        let resolvedTitle = title ?? defaultSessionTitle()
        let record = SessionRecord(
            title: resolvedTitle,
            workingDirectory: projectRoot,
            orderIndex: sessions.count
        )
        appendSession(record)
        ensureEngine(for: record.id, shell: shell)
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
        await engineStore.terminateEngine(for: id)
        let endDate = clock.now()
        do {
            try await repository.markEnded(id: id, at: endDate)
        } catch {
            state = .error("Failed to end session: \(error.localizedDescription)")
            logger.error("DB markEnded failed for session \(id): \(error)")
            return
        }

        // Re-check after the await — a concurrent operation may have already removed it.
        guard sessionIndex[id] != nil else { return }
        mutateSession(id: id) { $0.status = .ended(at: endDate) }
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
            state = .error("Failed to reopen session: \(error.localizedDescription)")
            logger.error("DB markReopened failed for session \(id): \(error)")
            return
        }
        mutateSession(id: id) { $0.status = .active }
        activateSession(id: id)
        logger.info("Reopened session \(id)")
    }
}

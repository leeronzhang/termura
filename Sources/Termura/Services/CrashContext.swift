import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "CrashContext")

/// Significant event recorded in the crash context ring buffer.
struct CrashEvent: Codable, Sendable {
    let timestamp: Date
    let category: String
    let message: String
}

/// Point-in-time application state snapshot for post-crash diagnostics.
struct CrashSnapshot: Codable, Sendable {
    let timestamp: Date
    let activeSessionCount: Int
    let dbHealth: String
    let recentEvents: [CrashEvent]
    let counters: [String: Int]
    let gauges: [String: Double]
}

/// Captures and persists structured crash context to UserDefaults (crash-safe storage).
/// Maintains a ring buffer of significant events and periodic state snapshots.
actor CrashContext {
    private let metrics: any MetricsCollectorProtocol
    private var ringBuffer: [CrashEvent] = []
    private let bufferCapacity: Int

    private static let eventsKey = "com.termura.crashEvents"
    private static let snapshotKey = "com.termura.crashContext"

    // MARK: - Init

    init(
        metrics: any MetricsCollectorProtocol,
        bufferCapacity: Int = AppConfig.CrashDiagnostics.ringBufferCapacity
    ) {
        self.metrics = metrics
        self.bufferCapacity = bufferCapacity
    }

    // MARK: - Event recording

    /// Record a significant event into the ring buffer.
    func recordEvent(category: String, message: String) {
        let event = CrashEvent(timestamp: Date(), category: category, message: message)
        if ringBuffer.count >= bufferCapacity {
            ringBuffer.removeFirst()
        }
        ringBuffer.append(event)
        persistEvents()
    }

    // MARK: - Snapshot

    /// Capture a full state snapshot and persist to UserDefaults.
    func captureSnapshot(
        activeSessionCount: Int,
        dbHealth: DBHealthStatus
    ) async {
        let snap = await metrics.snapshot()
        let counterDict = Dictionary(
            uniqueKeysWithValues: snap.counters.map { ($0.key.rawValue, $0.value) }
        )
        let gaugeDict = Dictionary(
            uniqueKeysWithValues: snap.gauges.map { ($0.key.rawValue, $0.value) }
        )
        let snapshot = CrashSnapshot(
            timestamp: Date(),
            activeSessionCount: activeSessionCount,
            dbHealth: dbHealth.rawValue,
            recentEvents: ringBuffer,
            counters: counterDict,
            gauges: gaugeDict
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        } catch {
            logger.error("Failed to persist crash snapshot: \(error)")
        }
    }

    // MARK: - Recovery

    /// Retrieve crash context from a prior run. Call at launch before clearing.
    static func loadPriorCrashContext() -> CrashSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: snapshotKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(CrashSnapshot.self, from: data)
        } catch {
            logger.warning("Failed to decode prior crash context: \(error)")
            return nil
        }
    }

    /// Clear persisted crash data (call after successful launch).
    static func clearPersistedData() {
        UserDefaults.standard.removeObject(forKey: eventsKey)
        UserDefaults.standard.removeObject(forKey: snapshotKey)
    }

    // MARK: - Private

    private func persistEvents() {
        do {
            let data = try JSONEncoder().encode(ringBuffer)
            UserDefaults.standard.set(data, forKey: Self.eventsKey)
        } catch {
            logger.error("Failed to persist crash events: \(error)")
        }
    }
}

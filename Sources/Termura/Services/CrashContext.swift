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

/// Captures and persists structured crash context to UserDefaults (crash-safe primary storage)
/// and to `~/.termura/diagnostics/crash_context.json` (file-backed fallback).
/// Maintains a ring buffer of significant events and periodic state snapshots.
actor CrashContext {
    private let metrics: any MetricsCollectorProtocol
    private var ringBuffer: [CrashEvent] = []
    private let bufferCapacity: Int
    private let userDefaults: any UserDefaultsStoring

    private static let eventsKey = "com.termura.crashEvents"
    private static let snapshotKey = "com.termura.crashContext"

    // MARK: - Init

    init(
        metrics: any MetricsCollectorProtocol,
        bufferCapacity: Int = AppConfig.CrashDiagnostics.ringBufferCapacity,
        userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) {
        self.metrics = metrics
        self.bufferCapacity = bufferCapacity
        self.userDefaults = userDefaults
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

    /// Capture a full state snapshot and persist to UserDefaults + file backup.
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
            // Primary: UserDefaults (crash-safe, survives hard kills)
            userDefaults.set(data, forKey: Self.snapshotKey)
            // Secondary: file backup (survives UserDefaults corruption)
            do {
                try Self.writeSnapshotToFile(data)
            } catch {
                logger.error("Failed to write crash snapshot to file: \(error)")
            }
        } catch {
            logger.error("Failed to persist crash snapshot: \(error)")
        }
    }

    // MARK: - Recovery

    /// Retrieve crash context from a prior run. Checks UserDefaults first, file as fallback.
    /// Call at launch before clearing.
    static func loadPriorCrashContext(
        userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) -> CrashSnapshot? {
        // Primary: UserDefaults
        if let data = userDefaults.data(forKey: snapshotKey) {
            return decodeCrashSnapshot(data)
        }
        // Fallback: file backup (UserDefaults may have been cleared by the OS)
        do {
            let data = try Data(contentsOf: crashContextFileURL)
            return decodeCrashSnapshot(data)
        } catch {
            logger.debug("No file-backed crash context: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clear persisted crash data (call after successful launch).
    static func clearPersistedData(
        userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) {
        userDefaults.removeObject(forKey: eventsKey)
        userDefaults.removeObject(forKey: snapshotKey)
        do {
            try FileManager.default.removeItem(at: crashContextFileURL)
        } catch {
            logger.debug("Could not remove crash context file: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func persistEvents() {
        do {
            let data = try JSONEncoder().encode(ringBuffer)
            userDefaults.set(data, forKey: Self.eventsKey)
        } catch {
            logger.error("Failed to persist crash events: \(error)")
        }
    }

    private static func decodeCrashSnapshot(_ data: Data) -> CrashSnapshot? {
        do {
            return try JSONDecoder().decode(CrashSnapshot.self, from: data)
        } catch {
            logger.warning("Failed to decode crash context: \(error)")
            return nil
        }
    }

    private static func writeSnapshotToFile(_ data: Data) throws {
        let dir = crashContextFileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: nil
        )
        try data.write(to: crashContextFileURL, options: .atomic)
    }

    private static var crashContextFileURL: URL {
        URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.CrashDiagnostics.diagnosticsDirectoryName)
            .appendingPathComponent(AppConfig.CrashDiagnostics.crashContextFileName)
    }
}

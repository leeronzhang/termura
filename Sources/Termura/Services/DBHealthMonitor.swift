import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "DBHealthMonitor")

/// Health status levels for the database connection pool.
enum DBHealthStatus: String, Sendable, Codable {
    case healthy
    case degraded
    case unhealthy
}

/// Periodic health monitor for the GRDB DatabasePool.
/// Runs a lightweight `SELECT 1` probe at a configurable interval and tracks
/// consecutive failures to provide graduated degradation status.
actor DBHealthMonitor {
    // MARK: - Dependencies

    private let db: any DatabaseServiceProtocol
    private let metrics: any MetricsCollectorProtocol
    private let clock: any AppClock

    // MARK: - Configuration

    private let probeInterval: Duration
    private let degradedThreshold: Int
    private let unhealthyThreshold: Int

    // MARK: - State

    private var consecutiveFailures = 0
    private(set) var status: DBHealthStatus = .healthy
    // nonisolated(unsafe): deinit is nonisolated; last-reference guarantee makes
    // the access free of data races — no concurrent mutation is possible at deinit time.
    nonisolated(unsafe) private var monitorTask: Task<Void, Never>?

    // MARK: - Init

    init(
        db: any DatabaseServiceProtocol,
        metrics: any MetricsCollectorProtocol,
        clock: any AppClock = LiveClock(),
        probeInterval: Duration = AppConfig.Health.probeInterval,
        degradedThreshold: Int = AppConfig.Health.degradedThreshold,
        unhealthyThreshold: Int = AppConfig.Health.unhealthyThreshold
    ) {
        self.db = db
        self.metrics = metrics
        self.clock = clock
        self.probeInterval = probeInterval
        self.degradedThreshold = degradedThreshold
        self.unhealthyThreshold = unhealthyThreshold
    }

    deinit {
        monitorTask?.cancel()
    }

    // MARK: - Lifecycle

    func start() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await runLoop()
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    // MARK: - Probe loop

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: probeInterval)
            } catch {
                return
            }
            await probe()
        }
    }

    private func probe() async {
        do {
            let _: Int = try await db.read { database in
                try Int.fetchOne(database, sql: "SELECT 1") ?? 0
            }
            if consecutiveFailures > 0 {
                logger.info("DB health restored after \(self.consecutiveFailures) failure(s)")
            }
            consecutiveFailures = 0
            status = .healthy
        } catch {
            consecutiveFailures += 1
            let previous = status
            if consecutiveFailures >= unhealthyThreshold {
                status = .unhealthy
            } else if consecutiveFailures >= degradedThreshold {
                status = .degraded
            }
            if status != previous {
                logger.warning(
                    "DB health changed: \(self.status.rawValue) (failures=\(self.consecutiveFailures))"
                )
            }
        }
    }
}

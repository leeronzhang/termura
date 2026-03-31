import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ContextWindowMonitor")

/// Alert emitted when an agent's context usage exceeds a threshold.
struct ContextWindowAlert: Identifiable, Sendable {
    enum Level: String, Sendable {
        case warning
        case critical
    }

    let id: UUID = .init()
    let sessionID: SessionID
    let agentType: AgentType
    let level: Level
    let usageFraction: Double
    let estimatedTokens: Int
    let contextLimit: Int
}

/// Monitors agent context window usage and emits alerts when thresholds are crossed.
/// Uses a per-session cooldown to avoid spamming notifications.
actor ContextWindowMonitor {
    private var lastAlertTimes: [SessionID: Date] = [:]
    private let clock: any AppClock

    init(clock: any AppClock = LiveClock()) {
        self.clock = clock
    }

    /// Evaluates an agent state and returns an alert if a threshold is crossed
    /// and the cooldown period has elapsed.
    func evaluate(state: AgentState) -> ContextWindowAlert? {
        guard state.isContextWarning else { return nil }

        if let lastTime = lastAlertTimes[state.sessionID] {
            let elapsed = clock.now().timeIntervalSince(lastTime)
            guard elapsed >= AppConfig.ContextWindow.notificationCooldownSeconds else {
                return nil
            }
        }

        lastAlertTimes[state.sessionID] = clock.now()
        let level: ContextWindowAlert.Level = state.isContextCritical ? .critical : .warning

        logger.info(
            "Context \(level.rawValue): \(state.agentType.rawValue) at \(Int(state.contextUsageFraction * 100))%"
        )

        return ContextWindowAlert(
            sessionID: state.sessionID,
            agentType: state.agentType,
            level: level,
            usageFraction: state.contextUsageFraction,
            estimatedTokens: state.tokenCount,
            contextLimit: state.contextWindowLimit
        )
    }

    /// Resets cooldown for a session (e.g., on session close or agent restart).
    func reset(for sessionID: SessionID) {
        lastAlertTimes.removeValue(forKey: sessionID)
    }
}

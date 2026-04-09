import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.termura.app", category: "NotificationService")

protocol NotificationServiceProtocol: Sendable {
    func notifyIfLong(_ chunk: OutputChunk) async
    func notifyContextWindow(_ alert: ContextWindowAlert) async
}

/// Requests UNUserNotification permission and fires a system alert when
/// a command runs longer than `AppConfig.Runtime.longCommandThresholdSeconds`.
actor NotificationService: NotificationServiceProtocol {
    init() {
        // Lifecycle: one-shot init — permission request; app functions without notification permission.
        Task { await requestAuthorization() }
    }

    func notifyIfLong(_ chunk: OutputChunk) async {
        guard let finished = chunk.finishedAt else { return }
        let duration = finished.timeIntervalSince(chunk.startedAt)
        guard duration > AppConfig.Runtime.longCommandThresholdSeconds else { return }

        let content = UNMutableNotificationContent()
        content.title = sanitizedCommandName(chunk.commandText)
        let exitStr = chunk.exitCode.map { "exit \($0)" } ?? "completed"
        content.body = "\(exitStr) · \(formattedDuration(duration))"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: chunk.id.uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Failed to schedule notification: \(error)")
        }
    }

    func notifyContextWindow(_ alert: ContextWindowAlert) async {
        let isCritical = alert.level == .critical
        let content = UNMutableNotificationContent()
        content.title = "\(alert.agentType.rawValue) context \(isCritical ? "nearly full" : "getting full")"
        content.body = String(
            format: "%.0f%% used (%dk / %dk tokens)",
            alert.usageFraction * 100,
            alert.estimatedTokens / 1000,
            alert.contextLimit / 1000
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ctx-\(alert.sessionID)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("Failed to schedule context window notification: \(error)")
        }
    }

    // MARK: - Private

    private func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
            if !granted {
                logger.info("Notification permission not granted by user")
            }
        } catch {
            logger.error("Notification authorization error: \(error)")
        }
    }

    /// Extracts only the command basename (no arguments) to prevent
    /// credential/token leakage via macOS Notification Center history.
    private func sanitizedCommandName(_ commandText: String) -> String {
        let trimmed = commandText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Command finished" }
        let firstToken = trimmed.components(separatedBy: .whitespaces).first ?? ""
        let basename = URL(fileURLWithPath: firstToken).lastPathComponent
        return basename.isEmpty ? "Command finished" : "\(basename) finished"
    }

    func formattedDuration(_ secs: TimeInterval) -> String {
        secs < 60
            ? String(format: "%.0fs", secs)
            : "\(Int(secs / 60))m \(Int(secs) % 60)s"
    }
}

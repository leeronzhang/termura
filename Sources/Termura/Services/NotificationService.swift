import Foundation
import OSLog
import UserNotifications

private let logger = Logger(subsystem: "com.termura.app", category: "NotificationService")

protocol NotificationServiceProtocol: Sendable {
    func notifyIfLong(_ chunk: OutputChunk) async
}

/// Requests UNUserNotification permission and fires a system alert when
/// a command runs longer than `AppConfig.Runtime.longCommandThresholdSeconds`.
actor NotificationService: NotificationServiceProtocol {

    init() {
        Task { await requestAuthorization() }
    }

    func notifyIfLong(_ chunk: OutputChunk) async {
        guard let finished = chunk.finishedAt else { return }
        let duration = finished.timeIntervalSince(chunk.startedAt)
        guard duration > AppConfig.Runtime.longCommandThresholdSeconds else { return }

        let content = UNMutableNotificationContent()
        content.title = chunk.commandText.isEmpty ? "Command finished" : chunk.commandText
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

    private func formattedDuration(_ secs: TimeInterval) -> String {
        secs < 60
            ? String(format: "%.0fs", secs)
            : "\(Int(secs / 60))m \(Int(secs) % 60)s"
    }
}

// MARK: - Mock (Actor for test-safe mutation tracking)

actor MockNotificationService: NotificationServiceProtocol {
    private(set) var notifiedChunks: [OutputChunk] = []

    func notifyIfLong(_ chunk: OutputChunk) async {
        notifiedChunks.append(chunk)
    }
}

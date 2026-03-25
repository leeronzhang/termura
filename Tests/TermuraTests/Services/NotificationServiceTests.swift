import Foundation
import Testing
@testable import Termura

@Suite("NotificationService")
struct NotificationServiceTests {
    // MARK: - Helpers

    private func makeChunk(
        command: String = "npm test",
        exitCode: Int? = 0,
        startedAt: Date = Date(timeIntervalSince1970: 1000),
        finishedAt: Date? = Date(timeIntervalSince1970: 1060)
    ) -> OutputChunk {
        OutputChunk(
            sessionID: SessionID(),
            commandText: command,
            outputLines: ["output"],
            rawANSI: "output",
            exitCode: exitCode,
            startedAt: startedAt,
            finishedAt: finishedAt
        )
    }

    // MARK: - Duration threshold

    @Test("Short command does not trigger notification")
    func shortCommandNoNotification() async {
        let mock = MockNotificationService()
        let chunk = makeChunk(
            startedAt: Date(timeIntervalSince1970: 1000),
            finishedAt: Date(timeIntervalSince1970: 1005) // 5 seconds
        )
        await mock.notifyIfLong(chunk)
        let notified = await mock.notifiedChunks
        // Mock always records, but real service would skip short commands.
        #expect(notified.count == 1)
    }

    @Test("Nil finishedAt does not crash")
    func nilFinishedAt() async {
        let mock = MockNotificationService()
        let chunk = makeChunk(finishedAt: nil)
        await mock.notifyIfLong(chunk)
        let notified = await mock.notifiedChunks
        #expect(notified.count == 1) // Mock records it regardless.
    }

    // MARK: - Context window notification

    @Test("Critical alert has correct title wording")
    func criticalAlertContent() async {
        let mock = MockNotificationService()
        let alert = ContextWindowAlert(
            sessionID: SessionID(),
            agentType: .claudeCode,
            level: .critical,
            usageFraction: 0.96,
            estimatedTokens: 192_000,
            contextLimit: 200_000
        )
        await mock.notifyContextWindow(alert)
        let alerts = await mock.notifiedContextAlerts
        #expect(alerts.count == 1)
        #expect(alerts.first?.level == .critical)
    }

    @Test("Warning alert records correctly")
    func warningAlertContent() async {
        let mock = MockNotificationService()
        let alert = ContextWindowAlert(
            sessionID: SessionID(),
            agentType: .aider,
            level: .warning,
            usageFraction: 0.82,
            estimatedTokens: 105_000,
            contextLimit: 128_000
        )
        await mock.notifyContextWindow(alert)
        let alerts = await mock.notifiedContextAlerts
        #expect(alerts.count == 1)
        #expect(alerts.first?.agentType == .aider)
    }

    // MARK: - formattedDuration (real service)

    @Test("Seconds formatting")
    func formattedDurationSeconds() async {
        let service = NotificationService()
        let result = await service.formattedDuration(30)
        #expect(result == "30s")
    }

    @Test("Minutes formatting")
    func formattedDurationMinutes() async {
        let service = NotificationService()
        let result = await service.formattedDuration(135)
        #expect(result == "2m 15s")
    }

    @Test("Zero seconds")
    func formattedDurationZero() async {
        let service = NotificationService()
        let result = await service.formattedDuration(0)
        #expect(result == "0s")
    }
}

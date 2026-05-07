import Foundation
@testable import Termura

actor MockNotificationService: NotificationServiceProtocol {
    private(set) var notifiedChunks: [OutputChunk] = []
    private(set) var notifiedContextAlerts: [ContextWindowAlert] = []

    func notifyIfLong(_ chunk: OutputChunk) async {
        notifiedChunks.append(chunk)
    }

    func notifyContextWindow(_ alert: ContextWindowAlert) async {
        notifiedContextAlerts.append(alert)
    }
}

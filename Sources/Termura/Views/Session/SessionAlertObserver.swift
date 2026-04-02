import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionAlertObserver")

@MainActor
final class SessionAlertObserver {
    let agentCoordinator: AgentCoordinator
    let notificationService: (any NotificationServiceProtocol)?
    weak var viewModel: TerminalViewModel?

    private var riskAlertTask: AutoCancellableTask?
    private var contextWindowAlertTask: AutoCancellableTask?

    init(agentCoordinator: AgentCoordinator, notificationService: (any NotificationServiceProtocol)?) {
        self.agentCoordinator = agentCoordinator
        self.notificationService = notificationService
    }

    func inject(viewModel: TerminalViewModel) {
        self.viewModel = viewModel
        subscribeToAlerts()
    }

    private func subscribeToAlerts() {
        let riskStream = agentCoordinator.riskAlerts
        riskAlertTask = AutoCancellableTask(Task { [weak self] in
            for await risk in riskStream {
                guard let self, !Task.isCancelled else { break }
                guard viewModel?.pendingRiskAlert == nil else { continue }
                viewModel?.pendingRiskAlert = risk
            }
        })
        let ctxStream = agentCoordinator.contextWindowAlerts
        let notifService = notificationService
        contextWindowAlertTask = AutoCancellableTask(Task { [weak self] in
            for await alert in ctxStream {
                guard let self, !Task.isCancelled else { break }
                viewModel?.contextWindowAlert = alert
                Task { await notifService?.notifyContextWindow(alert) }
            }
        })
    }
}

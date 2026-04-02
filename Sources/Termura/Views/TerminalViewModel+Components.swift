import Foundation

// MARK: - Construction dependencies

extension TerminalViewModel {
    /// Groups the 7 construction-time dependencies. Required per CLAUDE.md §5:
    /// init with more than 6 parameters must pack them into a named struct.
    struct Components {
        let sessionID: SessionID
        let engine: any TerminalEngine
        let sessionStore: any SessionStoreProtocol
        let modeController: InputModeController
        let agentCoordinator: AgentCoordinator
        let outputProcessor: OutputProcessor
        let sessionServices: SessionServices
        let initialWorkingDirectory: String
        let clock: any AppClock
        let notificationService: (any NotificationServiceProtocol)? // Optional: observability, nil = no-op

        init(
            sessionID: SessionID,
            engine: any TerminalEngine,
            sessionStore: any SessionStoreProtocol,
            modeController: InputModeController,
            agentCoordinator: AgentCoordinator,
            outputProcessor: OutputProcessor,
            sessionServices: SessionServices,
            initialWorkingDirectory: String = AppConfig.Paths.homeDirectory,
            clock: any AppClock = LiveClock(),
            notificationService: (any NotificationServiceProtocol)? = nil // Optional: observability, nil = no-op
        ) {
            self.sessionID = sessionID
            self.engine = engine
            self.sessionStore = sessionStore
            self.modeController = modeController
            self.agentCoordinator = agentCoordinator
            self.outputProcessor = outputProcessor
            self.sessionServices = sessionServices
            self.initialWorkingDirectory = initialWorkingDirectory
            self.clock = clock
            self.notificationService = notificationService
        }
    }
}

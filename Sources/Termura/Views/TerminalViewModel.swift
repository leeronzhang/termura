import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")
/// ViewModel bridging the terminal engine with output chunking, token counting,
/// and session metadata; delegates agent detection, output processing, and session services.
@Observable
@MainActor
final class TerminalViewModel {
    // MARK: - Observable state

    var currentMetadata: SessionMetadata
    /// True while an interactive tool (Claude Code `>`) is showing its prompt.
    var isInteractivePrompt: Bool = false
    /// Currently pending risk alert (shown as sheet).
    var pendingRiskAlert: RiskAlert?
    /// Context window warning alert (shown as sheet).
    var contextWindowAlert: ContextWindowAlert?

    // MARK: - Dependencies

    let sessionID: SessionID
    let engine: any TerminalEngine
    let sessionStore: any SessionStoreProtocol
    let modeController: InputModeController
    let agentCoordinator: AgentCoordinator
    let outputProcessor: OutputProcessor
    let sessionServices: SessionServices
    let clock: any AppClock
    private let notificationService: (any NotificationServiceProtocol)?
    let sessionStartTime: Date = .init()

    // MARK: - Internal state (delegated to controller)

    let controller: TerminalSessionController

    // MARK: - Agent resume / Prompt detection

    /// Callback injected by TerminalAreaView: fired at most once when the first shell
    /// prompt is detected in a restored session.
    @ObservationIgnored var onShellPromptReadyForResume: (() -> Void)?

    init(_ components: Components) {
        sessionID = components.sessionID
        engine = components.engine
        sessionStore = components.sessionStore
        modeController = components.modeController
        agentCoordinator = components.agentCoordinator
        outputProcessor = components.outputProcessor
        sessionServices = components.sessionServices
        clock = components.clock
        notificationService = components.notificationService

        currentMetadata = SessionMetadata.empty(
            sessionID: components.sessionID,
            workingDirectory: components.initialWorkingDirectory
        )

        controller = TerminalSessionController(
            sessionID: components.sessionID,
            engine: components.engine,
            sessionStore: components.sessionStore,
            modeController: components.modeController,
            agentCoordinator: components.agentCoordinator,
            outputProcessor: components.outputProcessor,
            sessionServices: components.sessionServices,
            clock: components.clock,
            notificationService: components.notificationService
        )
        controller.inject(viewModel: self)
    }

    deinit {
        // controller's own deinit will handle task cancellation.
    }
}

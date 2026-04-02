import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionPromptObserver")

@MainActor
final class SessionPromptObserver {
    let engine: any TerminalEngine
    let modeController: InputModeController
    let clock: any AppClock
    weak var viewModel: TerminalViewModel?
    weak var controller: TerminalSessionController?

    private(set) var promptRecheckTask: AutoCancellableTask?

    init(
        engine: any TerminalEngine,
        modeController: InputModeController,
        clock: any AppClock
    ) {
        self.engine = engine
        self.modeController = modeController
        self.clock = clock
    }

    func inject(viewModel: TerminalViewModel, controller: TerminalSessionController) {
        self.viewModel = viewModel
        self.controller = controller
    }

    func tearDown() {
        promptRecheckTask?.cancel()
    }

    func schedulePromptRecheck() {
        promptRecheckTask?.cancel()
        promptRecheckTask = AutoCancellableTask(Task { [weak self, clock] in
            do {
                try await clock.sleep(for: AppConfig.UI.promptRecheckDelay)
            } catch is CancellationError {
                // CancellationError is expected — a newer output event supersedes this check
                return
            } catch {
                logger.warning("Prompt recheck delay failed: \(error.localizedDescription)")
                return
            }
            await self?.detectPromptFromScreenBuffer()
        })
    }

    private func detectPromptFromScreenBuffer() async {
        let screen = engine.linesNearCursor(above: 20)
        let lastLine = screen.last ?? ""
        let isPrompt = PromptDetector.detect(lastLine)
        viewModel?.isInteractivePrompt = isPrompt
        if isPrompt {
            modeController.switchToEditor()
            triggerAgentResumeIfNeeded()
        }
    }

    private func triggerAgentResumeIfNeeded() {
        guard let ctrl = controller, !ctrl.hasTriggeredAgentResume else { return }
        ctrl.hasTriggeredAgentResume = true
        viewModel?.onShellPromptReadyForResume?()
        viewModel?.onShellPromptReadyForResume = nil
    }
}

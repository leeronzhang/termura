import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "EditorViewModel")

/// ViewModel for the editor input area.
/// Manages text state, history navigation, and command submission.
@MainActor
final class EditorViewModel: ObservableObject {
    // MARK: - Published state

    @Published private(set) var currentText: String = ""

    // MARK: - Dependencies

    private var history: InputHistory
    private let modeController: InputModeController
    private let engine: any TerminalEngine
    /// Called after a command is submitted, for agent detection / session rename.
    var onCommandSubmit: ((String) -> Void)?
    /// Called after a command is submitted. Used by the Composer overlay to auto-dismiss.
    var onSubmit: (() -> Void)?

    // MARK: - Init

    init(engine: any TerminalEngine, modeController: InputModeController) {
        self.engine = engine
        self.modeController = modeController
        history = InputHistory()
    }

    // MARK: - Actions

    /// Submit the current text as a command to the terminal.
    /// Switches to passthrough so EditorInputView hides while the command runs.
    /// The view reappears when OSC 133 signals the next shell prompt.
    func submit() {
        let text = currentText
        history.push(text)
        currentText = ""
        modeController.switchToPassthrough()
        logger.debug("Submitting command length=\(text.count)")
        onCommandSubmit?(text)
        onSubmit?()
        // Lifecycle: single actor call — engine serializes internally; no cancellation needed.
        Task { await engine.send(text + "\r") }
    }

    /// Insert a literal newline at the cursor position.
    func insertNewline() {
        currentText += "\n"
    }

    /// Navigate to an older history entry.
    func navigatePrevious() {
        if let entry = history.navigatePrevious() {
            currentText = entry
        }
    }

    /// Navigate to a newer history entry or clear back to present.
    func navigateNext() {
        currentText = history.navigateNext() ?? ""
    }

    /// Appends text to the current editor content without replacing existing input.
    func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        currentText += text
    }

    /// Called by the NSViewRepresentable coordinator to sync text without cycles.
    func updateText(_ text: String) {
        guard text != currentText else { return }
        currentText = text
        history.resetCursor()
    }

    /// Send raw bytes to the PTY without appending a newline.
    /// Used for control sequences: Ctrl+C (ETX), Escape, etc.
    func sendRaw(_ text: String) {
        // Lifecycle: single actor call — engine serializes internally; no cancellation needed.
        Task { await engine.send(text) }
    }
}

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "EditorViewModel")

/// ViewModel for the editor input area.
/// Manages text state, history navigation, command submission, and file attachments.
@Observable
@MainActor
final class EditorViewModel {
    // MARK: - Observable state

    private(set) var currentText: String = ""
    private(set) var attachments: [ComposerAttachment] = []

    // MARK: - Dependencies

    private var history: InputHistory
    private let modeController: InputModeController
    private let engine: any TerminalEngine
    /// Callback injected by TerminalAreaView for agent detection / session rename after submit.
    /// Internal (not private): TerminalAreaView sets this at view-setup time. Not an implementation detail.
    @ObservationIgnored var onCommandSubmit: ((String) -> Void)?
    /// Callback injected by TerminalAreaView to dismiss the Composer overlay after submit.
    /// Internal (not private): TerminalAreaView sets and clears this externally.
    @ObservationIgnored var onSubmit: (() -> Void)?

    // MARK: - Init

    init(engine: any TerminalEngine, modeController: InputModeController) {
        self.engine = engine
        self.modeController = modeController
        history = InputHistory()
    }

    // MARK: - Attachment actions

    /// Appends a file attachment to the composer bar if the limit has not been reached.
    func addAttachment(_ url: URL, kind: ComposerAttachment.Kind, isTemporary: Bool) {
        guard attachments.count < AppConfig.Attachments.maxCount else { return }
        attachments.append(ComposerAttachment(id: UUID(), url: url, kind: kind, isTemporary: isTemporary))
    }

    /// Removes an attachment by ID, deleting its backing file if it was a temporary image.
    func removeAttachment(id: UUID) {
        guard let att = attachments.first(where: { $0.id == id }) else { return }
        attachments.removeAll { $0.id == id }
        if att.isTemporary {
            let url = att.url
            Task.detached {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    logger.debug("Temp attachment removal skipped: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Clears all attachments and deletes any temporary image files.
    /// Called on submit and when the owning session is closed.
    func clearAttachments() {
        let tempURLs = attachments.filter(\.isTemporary).map(\.url)
        attachments.removeAll()
        guard !tempURLs.isEmpty else { return }
        Task.detached {
            for url in tempURLs {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    logger.debug("Temp attachment removal skipped: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Command actions

    /// Submit the current text as a command to the terminal, prefixed with any attachment paths.
    /// Switches to passthrough so EditorInputView hides while the command runs.
    /// The view reappears when OSC 133 signals the next shell prompt.
    func submit() {
        let text = currentText
        let pathPrefix = attachments.map(\.url.path.shellEscaped).joined(separator: " ")
        let fullCommand: String = if pathPrefix.isEmpty {
            text
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pathPrefix
        } else {
            pathPrefix + " " + text
        }
        history.push(text)
        currentText = ""
        clearAttachments()
        modeController.switchToPassthrough()
        logger.debug("Submitting command length=\(fullCommand.count)")
        onCommandSubmit?(text) // user text only — used for agent detection
        onSubmit?()
        // ghostty_surface_text uses bracketed paste — embedded \r is literal, not "execute".
        // Send text first, then simulate Return key press to trigger shell execution.
        Task {
            await engine.send(fullCommand)
            await engine.pressReturn()
        }
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

    /// Replaces the current editor content with the given text.
    /// Used for programmatic pre-fill (e.g. agent resume auto-fill).
    func setText(_ text: String) {
        guard text != currentText else { return }
        currentText = text
        history.resetCursor()
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

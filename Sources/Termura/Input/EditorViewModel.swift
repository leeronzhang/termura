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
    private let fileManager: any FileManagerProtocol
    /// Callback injected by TerminalAreaView for agent detection / session rename after submit.
    /// Internal (not private): TerminalAreaView sets this at view-setup time. Not an implementation detail.
    @ObservationIgnored var onCommandSubmit: ((String) -> Void)?
    /// Callback injected by TerminalAreaView to dismiss the Composer overlay after submit.
    /// Internal (not private): TerminalAreaView sets and clears this externally.
    @ObservationIgnored var onSubmit: (() -> Void)?

    // MARK: - Init

    init(
        engine: any TerminalEngine,
        modeController: InputModeController,
        fileManager: any FileManagerProtocol = GlobalEnvironmentDefaults.fileManager
    ) {
        self.engine = engine
        self.modeController = modeController
        self.fileManager = fileManager
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
            let fileManager = fileManager
            // WHY: Temporary attachment cleanup performs filesystem I/O and must not block the caller.
            // OWNER: removeAttachment launches this one-shot detached delete for the removed attachment.
            // TEARDOWN: The detached task exits after the delete attempt and does not outlive cleanup.
            // TEST: Cover temp-attachment removal and non-fatal delete failures.
            Task.detached {
                do {
                    try fileManager.removeItem(at: url)
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
        let fileManager = fileManager
        // WHY: Bulk temp-file cleanup performs filesystem I/O and must leave the caller's actor.
        // OWNER: clearAttachments launches this one-shot detached delete batch.
        // TEARDOWN: The detached task exits after processing the captured URL list.
        // TEST: Cover submit/close cleanup deleting temp files and tolerating missing files.
        Task.detached {
            for url in tempURLs {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    logger.debug("Temp attachment removal skipped: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Command actions

    /// Submit text as a command to the terminal, prefixed with any attachment paths.
    /// Switches to passthrough so EditorInputView hides while the command runs.
    /// The view reappears when OSC 133 signals the next shell prompt.
    func submit(textOverride: String? = nil) {
        let text = textOverride ?? currentText
        if let textOverride, textOverride != currentText {
            currentText = textOverride
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }

        let submittedAttachments = attachments
        let pathPrefix = attachments.map(\.url.path.shellEscaped).joined(separator: " ")
        let fullCommand: String = if pathPrefix.isEmpty {
            text
        } else if trimmedText.isEmpty {
            pathPrefix
        } else {
            pathPrefix + " " + text
        }
        let submittedAttachmentIDs = Set(submittedAttachments.map(\.id))
        let tempURLsToDelete = submittedAttachments.filter(\.isTemporary).map(\.url)
        logSubmission(fullCommand: fullCommand, payloadSize: fullCommand.utf8.count)
        // Send text to PTY and press Return BEFORE dismissing the composer.
        // Dismiss must happen after send+pressReturn so the ghostty surface is in
        // a stable state (dismissComposer triggers SwiftUI view tree changes that could race).
        // Uses engine.send (ghostty_surface_text) rather than sendBytes because
        // composer text is always valid UTF-8; sendBytes routes through Ghostty's
        // binding-action text:\xHH parser which interprets each hex escape as a
        // Unicode codepoint and re-encodes it, corrupting multi-byte sequences.
        let capturedEngine = engine
        let capturedFileManager = fileManager
        Task {
            let delivered = await capturedEngine.send(fullCommand)
            guard delivered else {
                logger.error("Composer submit failed; preserving text and attachments")
                return
            }
            completeSuccessfulSubmit(text: text, attachmentIDs: submittedAttachmentIDs)
            onCommandSubmit?(text) // user text only — used for agent detection
            await capturedEngine.pressReturn()
            onSubmit?()
            guard !tempURLsToDelete.isEmpty else { return }
            // WHY: PTY bytes ≠ CLI consumed; give the downstream agent a buffer to
            // open the attachment file before we delete it. The 2s window is coarse
            // — there's no signal we can wait on without a roundtrip protocol.
            // OWNER: chained off the submit task; one-shot per submit() call.
            // TEARDOWN: detached delete loop is fire-and-forget; the OS reclaims any
            // missed temp files on next reboot.
            // TEST: cover submit-with-temp-image and assert file persists past send.
            Task.detached {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    // Non-critical: cancellation while waiting just means we skip
                    // cleanup this round; OS reclaims temp files at next reboot.
                    logger.debug("Temp attachment cleanup wait interrupted: \(error.localizedDescription)")
                    return
                }
                for url in tempURLsToDelete {
                    do {
                        try capturedFileManager.removeItem(at: url)
                    } catch {
                        logger.debug("Temp attachment removal skipped: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    private func logSubmission(fullCommand: String, payloadSize: Int) {
        let preview = String(fullCommand.prefix(256))
        logger.info(
            "Composer submit payload bytes=\(payloadSize, privacy: .public) preview=\(preview, privacy: .private)"
        )
    }

    private func completeSuccessfulSubmit(text: String, attachmentIDs: Set<UUID>) {
        history.push(text)
        if currentText == text {
            currentText = ""
        }
        attachments.removeAll { attachmentIDs.contains($0.id) }
        modeController.switchToPassthrough()
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

import AppKit
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "EditorTextView")

/// NSTextView subclass providing editor-grade input for the terminal.
/// Handles submit, newline insertion, and history navigation keys.
@MainActor
final class EditorTextView: NSTextView {
    // MARK: - Callbacks (wired by Coordinator)

    /// Called when the user submits the current text (Enter / Cmd+Enter).
    var submitHandler: ((String) -> Void)?
    /// Called when Shift+Enter is pressed (insert literal newline).
    var newlineHandler: (() -> Void)?
    /// Called when Up (true) or Down (false) is pressed on a single-line buffer.
    var historyNavigationHandler: ((Bool) -> Void)?

    // MARK: - Placeholder

    /// Placeholder text shown when the editor is empty. Drawn by overriding `draw(_:)`.
    var placeholderString: String? {
        didSet { needsDisplay = true }
    }

    // MARK: - Drag and drop

    /// Called when a file or image is dropped onto the editor.
    /// When set, drops are routed to the attachment bar instead of inline text insertion.
    /// Parameters: url, kind, isTemporary.
    var attachmentDropHandler: ((URL, ComposerAttachment.Kind, Bool) -> Void)?

    func setupDragTypes() {
        registerForDraggedTypes([.fileURL, .URL, .tiff, .png])
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        guard hasFileURL || hasImage else {
            return super.draggingEntered(sender)
        }
        return .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            if let handler = attachmentDropHandler {
                let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif"]
                urls.forEach { url in
                    let kind: ComposerAttachment.Kind = imageExtensions.contains(url.pathExtension.lowercased()) ? .image : .textFile
                    handler(url, kind, false)
                }
                return true
            }
            // Fallback: inline text insertion (no attachment bar wired).
            let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
            let insertion = string.isEmpty ? paths : " " + paths
            insertText(insertion, replacementRange: selectedRange())
            return true
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            if let handler = attachmentDropHandler {
                do {
                    let url = try saveTemporaryAttachmentImage(image)
                    handler(url, .image, true)
                    return true
                } catch {
                    logger.error("Attachment image save failed: \(error.localizedDescription)")
                    return false
                }
            }
            // Fallback: inline text insertion (no attachment bar wired).
            do {
                let url = try saveTemporaryAttachmentImage(image)
                let path = url.path.shellEscaped
                let insertion = string.isEmpty ? path : " " + path
                insertText(insertion, replacementRange: selectedRange())
                return true
            } catch {
                return false
            }
        }
        return super.performDragOperation(sender)
    }

    // MARK: - Paste override

    /// Intercepts Cmd+V to capture clipboard images as composer attachments.
    /// Plain-text paste falls through to NSTextView's default handler.
    /// Without this override, isRichText=false causes NSTextView to silently
    /// discard image data — leaving attachments empty and the path missing from submit().
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let hasFileURL = pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
        if !hasFileURL, hasImage,
           let handler = attachmentDropHandler,
           let image = NSImage(pasteboard: pb) {
            do {
                let url = try saveTemporaryAttachmentImage(image)
                handler(url, .image, true)
            } catch {
                logger.error("Clipboard image paste failed: \(error.localizedDescription)")
            }
            return
        }
        super.paste(sender)
    }

    // MARK: - Control sequence callback

    /// Called when a PTY control sequence is typed (Ctrl+C, Escape, etc.).
    /// The receiver should forward the raw bytes to the engine without appending \n.
    var controlSequenceHandler: ((String) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let placeholder = placeholderString else { return }
        let xInset = (textContainerInset.width) + (textContainer?.lineFragmentPadding ?? 0)
        let yInset = textContainerInset.height
        let drawRect = NSRect(
            x: xInset,
            y: yInset,
            width: dirtyRect.width - xInset,
            height: dirtyRect.height - yInset
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.placeholderTextColor,
            .font: font ?? NSFont(name: AppConfig.Fonts.terminalFamily, size: AppConfig.Fonts.editorSize)
                ?? NSFont.monospacedSystemFont(ofSize: AppConfig.Fonts.editorSize, weight: .regular),
            .strikethroughStyle: 0
        ]
        NSAttributedString(string: placeholder, attributes: attrs).draw(in: drawRect)
    }

    // MARK: - Key handling

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isShift = flags.contains(.shift)
        let isCommand = flags.contains(.command)
        let isCtrl = flags.contains(.control)

        // Escape → send ESC byte to PTY (interrupt Claude Code prompt, etc.)
        if event.keyCode == KeyCode.escape {
            controlSequenceHandler?("\u{1B}")
            return
        }

        // Ctrl+letter -> send raw control byte to PTY (Ctrl+C = 0x03, Ctrl+D = 0x04 etc.)
        if isCtrl, !isCommand, !isShift,
           let chars = event.charactersIgnoringModifiers,
           let scalar = chars.unicodeScalars.first {
            let byte = UInt8(scalar.value & 0x1F)
            if let seq = String(bytes: [byte], encoding: .utf8) {
                controlSequenceHandler?(seq)
                return
            }
        }

        switch event.keyCode {
        case KeyCode.returnKey:
            handleReturn(isShift: isShift, isCommand: isCommand)
        case KeyCode.upArrow:
            handleUpArrow(originalEvent: event)
        case KeyCode.downArrow:
            handleDownArrow(originalEvent: event)
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Private key handlers

    private func handleReturn(isShift: Bool, isCommand: Bool) {
        if isShift {
            newlineHandler?()
        } else {
            // Enter or Cmd+Enter both submit
            submitHandler?(string)
        }
    }

    private func handleUpArrow(originalEvent: NSEvent) {
        if isSingleLine {
            historyNavigationHandler?(true)
        } else {
            super.keyDown(with: originalEvent)
        }
    }

    private func handleDownArrow(originalEvent: NSEvent) {
        if isSingleLine {
            historyNavigationHandler?(false)
        } else {
            super.keyDown(with: originalEvent)
        }
    }

    private var isSingleLine: Bool {
        !string.contains("\n")
    }
}

// MARK: - Key codes

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let escape: UInt16 = 53
}

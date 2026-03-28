import AppKit

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
            let paths = urls.map(\.path.shellEscaped).joined(separator: " ")
            let insertion = string.isEmpty ? paths : " " + paths
            insertText(insertion, replacementRange: selectedRange())
            return true
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            do {
                let url = try saveTemporaryImage(image)
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

        private func saveTemporaryImage(_ image: NSImage) throws -> URL {
        let homeURL = FileManager.default.homeDirectoryForCurrentUser
        let tmpDir = homeURL.appendingPathComponent(AppConfig.DragDrop.tempImageSubdirectory)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let name = "\(AppConfig.DragDrop.imagePastePrefix)-\(Int(Date().timeIntervalSince1970)).\(AppConfig.DragDrop.imagePasteExtension)"
        let fileURL = tmpDir.appendingPathComponent(name)
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            throw EditorImageSaveError.conversionFailed
        }
        try png.write(to: fileURL)
        return fileURL
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

// MARK: - Supporting types

private enum EditorImageSaveError: Error {
    case conversionFailed
}

// MARK: - Key codes

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
    static let escape: UInt16 = 53
}

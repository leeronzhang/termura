import AppKit
import os

private let logger = Logger(subsystem: "dev.termura", category: "MarkdownTextView")

/// NSTextView subclass for Markdown editing.
/// Uses plain monospaced styling; Highlightr syntax highlighting is disabled
/// until the SPM resource bundle issue (Highlightr_Highlightr) is resolved.
final class MarkdownTextView: NSTextView {

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { preconditionFailure("Use init(frame:textContainer:)") }

    private func setup() {
        isRichText = false
        isEditable = true
        isSelectable = true
        font = NSFont(name: AppConfig.Fonts.terminalFamily, size: AppConfig.Fonts.notesSize)
            ?? .monospacedSystemFont(ofSize: AppConfig.Fonts.notesSize, weight: .regular)
        textContainerInset = NSSize(width: 12, height: 12)
        allowsUndo = true
        backgroundColor = .textBackgroundColor
    }

    func applyHighlighting(to text: String) {
        let savedRange = selectedRange()
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont(name: AppConfig.Fonts.terminalFamily, size: AppConfig.Fonts.notesSize)
                    ?? NSFont.monospacedSystemFont(ofSize: AppConfig.Fonts.notesSize, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
        )
        textStorage?.setAttributedString(attributed)
        let length = textStorage?.length ?? 0
        let clampedLocation = min(savedRange.location, length)
        let clampedLength = min(savedRange.length, length - clampedLocation)
        setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
    }
}

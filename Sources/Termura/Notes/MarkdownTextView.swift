import AppKit
import Highlightr

/// NSTextView subclass with live Markdown syntax highlighting via Highlightr.
final class MarkdownTextView: NSTextView {
    private let highlightr = Highlightr()

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
        font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textContainerInset = NSSize(width: 12, height: 12)
        allowsUndo = true
        highlightr?.setTheme(to: "github")
        backgroundColor = .textBackgroundColor
    }

    func applyHighlighting(to text: String) {
        guard let highlightr,
              let attributed = highlightr.highlight(text, as: "markdown") else { return }
        let savedRange = selectedRange()
        textStorage?.setAttributedString(attributed)
        // Clamp saved range to new string bounds to avoid out-of-range crash
        let length = textStorage?.length ?? 0
        let clampedLocation = min(savedRange.location, length)
        let clampedLength = min(savedRange.length, length - clampedLocation)
        setSelectedRange(NSRange(location: clampedLocation, length: clampedLength))
    }
}

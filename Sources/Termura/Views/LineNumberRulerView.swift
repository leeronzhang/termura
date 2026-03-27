import AppKit
import OSLog

private let rulerLogger = Logger(subsystem: "com.termura.app", category: "LineNumberRulerView")

// MARK: - Line Number Ruler

@MainActor
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var fontFamily: String
    private var fontSize: CGFloat
    private var lineSpacing: CGFloat

    init(
        textView: NSTextView,
        fontFamily: String,
        fontSize: CGFloat,
        lineSpacing: CGFloat
    ) {
        self.textView = textView
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = AppConfig.UI.lineNumberRulerWidth
        clientView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsRedraw),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(needsRedraw),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    func updateFont(family: String, size: CGFloat) {
        guard family != fontFamily || size != fontSize else { return }
        fontFamily = family
        fontSize = size
        needsDisplay = true
    }

    @objc private func needsRedraw(_ notification: Notification) {
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Clip to bounds to prevent drawing outside the ruler area
        let clippedRect = dirtyRect.intersection(bounds)
        guard !clippedRect.isEmpty else { return }
        // Fill background to hide the default ruler separator line.
        let bg = textView?.backgroundColor ?? .textBackgroundColor
        bg.setFill()
        clippedRect.fill()
        drawHashMarksAndLabels(in: clippedRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        guard text.length > 0 else { return }

        layoutManager.ensureLayout(for: textContainer)

        let attrs = rulerAttributes()
        let containerOrigin = textView.textContainerOrigin
        let visibleRect = textView.visibleRect
        let margin: CGFloat = (fontSize + lineSpacing) * 2

        // Pre-build a char-offset → line-number lookup (O(n) once, O(1) per query)
        let lineNumberAt = buildLineNumberLookup(text: text)

        // Use enumerateLineFragments to get exact Y positions for every visual line.
        let fullGlyphRange = layoutManager.glyphRange(for: textContainer)
        var lastDrawnLine = -1

        layoutManager.enumerateLineFragments(
            forGlyphRange: fullGlyphRange
        ) { lineRect, _, _, glyphRange, stop in
            let yInTextView = lineRect.origin.y + containerOrigin.y

            // Skip fragments well above visible area
            if yInTextView + lineRect.height < visibleRect.origin.y - margin { return }
            // Stop well below visible area
            if yInTextView > visibleRect.maxY + margin {
                stop.pointee = true
                return
            }

            let charRange = layoutManager.characterRange(
                forGlyphRange: glyphRange, actualGlyphRange: nil
            )
            let charIdx = min(charRange.location, lineNumberAt.count - 1)
            let lineNumber = charIdx >= 0 ? lineNumberAt[charIdx] : 1

            // Only draw for the first fragment of each logical line (skip soft-wrapped continuations)
            guard lineNumber != lastDrawnLine else { return }
            lastDrawnLine = lineNumber

            self.drawNumber(
                lineNumber,
                lineRect: lineRect,
                containerOrigin: containerOrigin,
                attrs: attrs
            )
        }

        // Handle the extra line fragment (empty line after trailing \n)
        let extraRect = layoutManager.extraLineFragmentRect
        if extraRect.height > 0 {
            let yInTextView = extraRect.origin.y + containerOrigin.y
            if yInTextView >= visibleRect.origin.y - margin,
               yInTextView <= visibleRect.maxY + margin {
                let lastLine = (lastDrawnLine > 0 ? lastDrawnLine : 0) + 1
                drawNumber(lastLine, lineRect: extraRect, containerOrigin: containerOrigin, attrs: attrs)
            }
        }
    }

    // MARK: - Helpers

    /// Builds an array mapping each character offset to its 1-based logical line number.
    /// Index i holds the line number for character at offset i. O(n) construction, O(1) lookup.
    private func buildLineNumberLookup(text: NSString) -> [Int] {
        let len = text.length
        guard len > 0 else { return [] }
        var lookup = [Int](repeating: 1, count: len)
        var line = 1
        for i in 0 ..< len {
            lookup[i] = line
            if text.character(at: i) == 0x0A { line += 1 }
        }
        return lookup
    }

    private func drawNumber(
        _ lineNumber: Int,
        lineRect: NSRect,
        containerOrigin: NSPoint,
        attrs: [NSAttributedString.Key: Any]
    ) {
        guard let textView else { return }

        let yInTextView = lineRect.origin.y + containerOrigin.y
        let yInRuler = convert(NSPoint(x: 0, y: yInTextView), from: textView).y

        let numStr = "\(lineNumber)" as NSString
        let strSize = numStr.size(withAttributes: attrs)

        // Vertically center in the line fragment
        let drawY = yInRuler + (lineRect.height - strSize.height) / 2

        // Right-align within a 3-digit block, centered across the full visual gutter
        // (ruler width + text container inset up to the level-0 guide line)
        let insetWidth = textView.textContainerInset.width
        let totalGutter = ruleThickness + insetWidth
        let refWidth = NSString("000").size(withAttributes: attrs).width
        let blockX = (totalGutter - refWidth) / 2
        let drawX = blockX + refWidth - strSize.width

        numStr.draw(at: NSPoint(x: drawX, y: drawY), withAttributes: attrs)
    }

    private func rulerAttributes() -> [NSAttributedString.Key: Any] {
        let rulerFontSize = max(fontSize - AppConfig.UI.lineNumberFontSizeReduction, FontSettings.minSize)
        let rulerFont = NSFont(name: fontFamily, size: rulerFontSize)
            ?? NSFont.monospacedDigitSystemFont(ofSize: rulerFontSize, weight: .regular)
        return [
            .font: rulerFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }
}

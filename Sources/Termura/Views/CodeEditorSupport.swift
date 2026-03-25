import AppKit
import OSLog

private let supportLogger = Logger(subsystem: "com.termura.app", category: "CodeEditorSupport")

// MARK: - Markdown Syntax Dimmer

/// Applies lightweight syntax dimming to Markdown content:
/// syntax characters (#, *, -, `, >, etc.) are rendered in a muted color
/// while the actual content text stays at normal color.
@MainActor
enum MarkdownSyntaxDimmer {
    static func apply(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        let text = textStorage.string
        guard !text.isEmpty else { return }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        let normalFont = textView.font ?? NSFont.monospacedSystemFont(
            ofSize: AppConfig.Fonts.editorSize, weight: .regular
        )
        let normalColor = NSColor.textColor
        let dimColor = NSColor.tertiaryLabelColor

        // Reset to normal
        textStorage.beginEditing()
        textStorage.addAttributes([
            .foregroundColor: normalColor,
            .font: normalFont
        ], range: fullRange)

        dimLineBasedSyntax(textStorage: textStorage, text: text, dimColor: dimColor)
        dimInlinePatterns(textStorage: textStorage, dimColor: dimColor)

        textStorage.endEditing()
    }

    /// Dims line-based Markdown syntax: headings, block quotes, list markers, horizontal rules.
    private static func dimLineBasedSyntax(
        textStorage: NSTextStorage,
        text: String,
        dimColor: NSColor
    ) {
        let nsText = text as NSString
        let textLength = nsText.length
        var lineStart = 0

        while lineStart < textLength {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let line = nsText.substring(with: lineRange)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            dimHeading(trimmed: trimmed, line: line, lineRange: lineRange, textStorage: textStorage, dimColor: dimColor)
            dimBlockQuote(trimmed: trimmed, line: line, lineRange: lineRange, textStorage: textStorage, dimColor: dimColor)
            dimListMarker(trimmed: trimmed, line: line, lineRange: lineRange, textStorage: textStorage, dimColor: dimColor)
            dimHorizontalRule(trimmed: trimmed, lineRange: lineRange, textStorage: textStorage, dimColor: dimColor)

            lineStart = NSMaxRange(lineRange)
        }
    }

    private static func dimHeading(
        trimmed: String, line: String, lineRange: NSRange,
        textStorage: NSTextStorage, dimColor: NSColor
    ) {
        guard trimmed.hasPrefix("#"),
              let hashEnd = trimmed.firstIndex(where: { $0 != "#" && $0 != " " }) else { return }
        let prefixCount = trimmed.distance(from: trimmed.startIndex, to: hashEnd)
        let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
        let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: prefixCount)
        if dimRange.location + dimRange.length <= textStorage.length {
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
        }
    }

    private static func dimBlockQuote(
        trimmed: String, line: String, lineRange: NSRange,
        textStorage: NSTextStorage, dimColor: NSColor
    ) {
        guard trimmed.hasPrefix(">") else { return }
        let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
        var prefixLen = 1
        if trimmed.count > 1 && trimmed[trimmed.index(after: trimmed.startIndex)] == " " {
            prefixLen = 2
        }
        let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: prefixLen)
        if dimRange.location + dimRange.length <= textStorage.length {
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
        }
    }

    private static func dimListMarker(
        trimmed: String, line: String, lineRange: NSRange,
        textStorage: NSTextStorage, dimColor: NSColor
    ) {
        guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") else { return }
        let leadingSpaces = line.count - line.drop(while: { $0 == " " }).count
        let dimRange = NSRange(location: lineRange.location + leadingSpaces, length: 2)
        if dimRange.location + dimRange.length <= textStorage.length {
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: dimRange)
        }
    }

    private static func dimHorizontalRule(
        trimmed: String, lineRange: NSRange,
        textStorage: NSTextStorage, dimColor: NSColor
    ) {
        guard trimmed.count >= 3 else { return }
        let chars = Set(trimmed)
        let isRule = chars == ["-"] || chars == ["*"] || chars == ["_"]
            || chars == ["-", " "] || chars == ["*", " "]
        if isRule {
            textStorage.addAttribute(.foregroundColor, value: dimColor, range: lineRange)
        }
    }

    /// Dims inline Markdown patterns: backtick code, bold, italic, fenced code markers.
    private static func dimInlinePatterns(textStorage: NSTextStorage, dimColor: NSColor) {
        dimPattern("`[^`]+`", in: textStorage, dimColor: dimColor, dimChars: 1)
        dimPattern("\\*\\*[^*]+\\*\\*", in: textStorage, dimColor: dimColor, dimChars: 2)
        dimPattern("(?<!\\*)\\*[^*]+\\*(?!\\*)", in: textStorage, dimColor: dimColor, dimChars: 1)
        dimPattern("^```.*$", in: textStorage, dimColor: dimColor, dimChars: nil, options: [.anchorsMatchLines])
    }

    /// Dims the first/last N characters of each regex match, or the entire match if `dimChars` is nil.
    private static func dimPattern(
        _ pattern: String,
        in storage: NSTextStorage,
        dimColor: NSColor,
        dimChars: Int?,
        options: NSRegularExpression.Options = []
    ) {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            supportLogger.warning("Invalid regex pattern '\(pattern)': \(error.localizedDescription)")
            return
        }
        let fullRange = NSRange(location: 0, length: storage.length)
        regex.enumerateMatches(in: storage.string, options: [], range: fullRange) { match, _, _ in
            guard let range = match?.range else { return }
            if let charCount = dimChars {
                if range.length > charCount * 2 {
                    let startRange = NSRange(location: range.location, length: charCount)
                    let endRange = NSRange(location: range.location + range.length - charCount, length: charCount)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: startRange)
                    storage.addAttribute(.foregroundColor, value: dimColor, range: endRange)
                }
            } else {
                storage.addAttribute(.foregroundColor, value: dimColor, range: range)
            }
        }
    }
}

// MARK: - Cmd+S support

final class SaveableTextView: NSTextView {
    var onSave: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
            onSave?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - Line Number Ruler

final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var fontFamily: String
    private var fontSize: CGFloat
    private var lineHeightMultiple: CGFloat

    /// Right-side padding between line number text and the ruler edge.
    private static let trailingPadding: CGFloat = 6

    init(
        textView: NSTextView,
        fontFamily: String,
        fontSize: CGFloat,
        lineHeightMultiple: CGFloat
    ) {
        self.textView = textView
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineHeightMultiple = lineHeightMultiple
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        ruleThickness = 40
        clientView = textView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    /// Called from `updateNSView` when font settings change.
    func updateFont(family: String, size: CGFloat) {
        guard family != fontFamily || size != fontSize else { return }
        fontFamily = family
        fontSize = size
        needsDisplay = true
    }

    @objc private func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        needsDisplay = true
    }

    /// Build ruler number attributes that match the editor font.
    /// Uses the same font family at a slightly smaller size so line numbers
    /// stay visually subordinate while sharing the same baseline metrics.
    /// NOTE: No paragraphStyle here — adding lineHeightMultiple inflates
    /// `size(withAttributes:).height`, which breaks the baseline calculation.
    private func rulerAttributes() -> [NSAttributedString.Key: Any] {
        let rulerFontSize = max(fontSize - 3, FontSettings.minSize)
        let rulerFont = NSFont(name: fontFamily, size: rulerFontSize)
            ?? NSFont.monospacedDigitSystemFont(ofSize: rulerFontSize, weight: .regular)
        return [
            .font: rulerFont,
            .foregroundColor: NSColor.secondaryLabelColor
        ]
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let text = textView.string as NSString
        guard text.length > 0 else { return }
        let containerOrigin = textView.textContainerOrigin
        let attrs = rulerAttributes()

        layoutManager.ensureLayout(for: textContainer)

        // Use character-index-based lookup so empty lines (control-only glyphs)
        // are never skipped. glyphRange(forBoundingRect:) misses them.
        let visibleRect = textView.visibleRect
        let margin = fontSize * lineHeightMultiple * 2

        let topY = max(visibleRect.origin.y - containerOrigin.y - margin, 0)
        let bottomY = visibleRect.maxY - containerOrigin.y + margin

        let topCharIdx = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: topY),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )
        let bottomCharIdx = layoutManager.characterIndex(
            for: NSPoint(x: 0, y: bottomY),
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        // Expand to full line boundaries
        let startLine = text.lineRange(for: NSRange(location: topCharIdx, length: 0))
        let endLine = text.lineRange(for: NSRange(
            location: min(bottomCharIdx, text.length - 1), length: 0
        ))
        let visibleCharRange = NSRange(
            location: startLine.location,
            length: NSMaxRange(endLine) - startLine.location
        )

        // Count newlines before visible range to get the starting line number
        var lineNumber = 1
        if visibleCharRange.location > 0 {
            let prefix = text.substring(to: visibleCharRange.location) as NSString
            var sr = NSRange(location: 0, length: prefix.length)
            while sr.length > 0 {
                let found = prefix.range(of: "\n", options: [], range: sr)
                if found.location == NSNotFound { break }
                lineNumber += 1
                let next = found.location + found.length
                sr = NSRange(location: next, length: prefix.length - next)
            }
        }

        // Iterate every line (including empty ones) by character range
        var index = visibleCharRange.location
        while index < NSMaxRange(visibleCharRange) {
            let lineRange = text.lineRange(for: NSRange(location: index, length: 0))

            // Get this line's glyph range — works for empty lines too (\n has a glyph)
            let lineGlyphRange = layoutManager.glyphRange(
                forCharacterRange: lineRange, actualCharacterRange: nil
            )
            guard lineGlyphRange.length > 0 else {
                lineNumber += 1
                index = NSMaxRange(lineRange)
                continue
            }

            let lineRect = layoutManager.lineFragmentRect(
                forGlyphAt: lineGlyphRange.location, effectiveRange: nil
            )
            let baseline = layoutManager.location(forGlyphAt: lineGlyphRange.location)

            // lineRect is in textContainer coords — add containerOrigin for textView coords
            let yInTextView = lineRect.origin.y + containerOrigin.y
            let yInRuler = convert(NSPoint(x: 0, y: yInTextView), from: textView).y

            let numStr = "\(lineNumber)" as NSString
            let strSize = numStr.size(withAttributes: attrs)
            // Baseline-align using font ascender: draw(at:) y is the top of the string,
            // so top = baseline - ascender gives correct baseline alignment.
            let rulerFont = attrs[.font] as? NSFont
            let ascender = rulerFont?.ascender ?? strSize.height
            let baselineInRuler = yInRuler + baseline.y
            let drawPoint = NSPoint(
                x: ruleThickness - strSize.width - Self.trailingPadding,
                y: baselineInRuler - ascender
            )
            numStr.draw(at: drawPoint, withAttributes: attrs)

            lineNumber += 1
            index = NSMaxRange(lineRange)
        }
    }
}

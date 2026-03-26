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

    /// Applies only the Markdown dim colors to the text storage (no editing batch, no font/reset).
    /// Called from CodeEditorTextViewRepresentable which manages its own editing batch.
    static func applyColors(to textStorage: NSTextStorage, range: NSRange) {
        let text = textStorage.string
        guard !text.isEmpty else { return }
        let dimColor = NSColor.tertiaryLabelColor
        dimLineBasedSyntax(textStorage: textStorage, text: text, dimColor: dimColor)
        dimInlinePatterns(textStorage: textStorage, dimColor: dimColor)
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
    /// Number of spaces per indent level for drawing indent guides.
    var indentWidth: Int = 4

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else {
            return super.performKeyEquivalent(with: event)
        }
        // Handle standard macOS editing shortcuts explicitly so SwiftUI
        // command handlers don't intercept them before the text view.
        switch event.charactersIgnoringModifiers {
        case "s":
            onSave?()
            return true
        case "a":
            selectAll(nil)
            return true
        case "c":
            copy(nil)
            return true
        case "v":
            paste(nil)
            return true
        case "x":
            cut(nil)
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        // Shrink cursor rect to match font height instead of full line height (which includes lineSpacing).
        guard let resolvedFont = font else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
            return
        }
        let fontHeight = resolvedFont.ascender - resolvedFont.descender
        var adjusted = rect
        adjusted.size.height = fontHeight
        super.drawInsertionPoint(in: adjusted, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        // Expand the dirty rect slightly for cursor redraw, but clamp to bounds
        var expanded = rect
        expanded.size.height += 4
        expanded = expanded.intersection(bounds)
        super.setNeedsDisplay(expanded, avoidAdditionalLayout: flag)
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        NSGraphicsContext.saveGraphicsState()
        bounds.intersection(rect).clip()
        drawIndentGuides(in: rect)
        NSGraphicsContext.restoreGraphicsState()
    }

    private struct IndentSegment { var minY: CGFloat; var maxY: CGFloat }

    /// Draws vertical indent guide lines at each indentation level.
    private func drawIndentGuides(in rect: NSRect) {
        guard let layoutManager, let textContainer,
              let resolvedFont = font else { return }
        let spaceWidth = NSString(" ").size(withAttributes: [.font: resolvedFont]).width
        let tabWidth = spaceWidth * CGFloat(indentWidth)
        guard tabWidth > 1 else { return }

        let origin = textContainerOrigin
        let xBase = origin.x + textContainerInset.width

        let guideColor = NSColor.separatorColor.withAlphaComponent(0.15)
        guideColor.setStroke()

        // Indented lines (including level 0): only where code has indentation
        let visibleGlyphRange = layoutManager.glyphRange(
            forBoundingRect: rect, in: textContainer
        )
        guard visibleGlyphRange.length > 0 else { return }
        let visibleCharRange = layoutManager.characterRange(
            forGlyphRange: visibleGlyphRange, actualGlyphRange: nil
        )

        let levelSegments = collectIndentSegments(
            charRange: visibleCharRange, origin: origin, layoutManager: layoutManager
        )
        guard !levelSegments.isEmpty else { return }
        strokeIndentGuides(levelSegments, xBase: xBase, tabWidth: tabWidth)
    }

    private func collectIndentSegments(
        charRange: NSRange, origin: NSPoint, layoutManager: NSLayoutManager
    ) -> [Int: [IndentSegment]] {
        let text = string as NSString
        var levelSegments: [Int: [IndentSegment]] = [:]
        // Max line height seen — used to bridge empty lines (merge gap tolerance)
        var maxLineHeight: CGFloat = 20
        var idx = charRange.location

        while idx < NSMaxRange(charRange) {
            let lineRange = text.lineRange(for: NSRange(location: idx, length: 0))
            let lineStr = text.substring(with: lineRange)
            let trimmed = lineStr.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty/whitespace-only lines — they don't break guide continuity
            if trimmed.isEmpty {
                idx = NSMaxRange(lineRange)
                continue
            }

            var spaces = 0
            for ch in lineStr {
                switch ch {
                case " ": spaces += 1
                case "\t": spaces += indentWidth
                default: break
                }
            }
            let level = spaces / indentWidth
            if level > 0 {
                let glyphRange = layoutManager.glyphRange(
                    forCharacterRange: lineRange, actualCharacterRange: nil
                )
                if glyphRange.length > 0 {
                    let lineRect = layoutManager.lineFragmentRect(
                        forGlyphAt: glyphRange.location, effectiveRange: nil
                    )
                    maxLineHeight = max(maxLineHeight, lineRect.height)
                    let top = lineRect.origin.y + origin.y
                    let bottom = lineRect.maxY + origin.y
                    for lv in 0..<level {
                        var segs = levelSegments[lv, default: []]
                        // Merge if gap is within a few line heights (bridges empty lines)
                        if var last = segs.last, (top - last.maxY) < maxLineHeight * 2 {
                            last.maxY = bottom
                            segs[segs.count - 1] = last
                        } else {
                            segs.append(IndentSegment(minY: top, maxY: bottom))
                        }
                        levelSegments[lv] = segs
                    }
                }
            }
            idx = NSMaxRange(lineRange)
        }
        return levelSegments
    }

    private func strokeIndentGuides(
        _ levelSegments: [Int: [IndentSegment]], xBase: CGFloat, tabWidth: CGFloat
    ) {
        // Color already set by caller (drawIndentGuides)
        let path = NSBezierPath()
        path.lineWidth = 1.0
        for (level, segments) in levelSegments {
            // Level N line sits at the start of indent level N (N * tabWidth from text origin)
            let xPos = (xBase + CGFloat(level) * tabWidth).rounded(.down) + 0.5
            for seg in segments {
                path.move(to: NSPoint(x: xPos, y: seg.minY))
                path.line(to: NSPoint(x: xPos, y: seg.maxY))
            }
        }
        path.stroke()
    }
}

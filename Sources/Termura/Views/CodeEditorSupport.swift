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

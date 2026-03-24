import Foundation

/// Utility for stripping ANSI escape sequences from terminal output.
/// Covers CSI sequences (ESC[...m), OSC sequences, and other common escapes.
enum ANSIStripper {
    // MARK: - Public API

    /// Strip all ANSI escape sequences from `text`.
    static func strip(_ text: String) -> String {
        guard text.contains("\u{1B}") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "\u{1B}" {
                let afterESC = text.index(after: index)
                index = skipEscapeSequence(in: text, from: afterESC)
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }
        return result
    }

    // MARK: - Private helpers

    /// Advance past an escape sequence starting at `index` (the byte after ESC).
    private static func skipEscapeSequence(in text: String, from index: String.Index) -> String.Index {
        guard index < text.endIndex else { return index }
        let next = text[index]

        switch next {
        case "[":
            return skipCSI(in: text, from: text.index(after: index))
        case "]":
            return skipOSC(in: text, from: text.index(after: index))
        case "(", ")", "*", "+":
            // Designate character set — one extra byte
            let step1 = text.index(after: index)
            return step1 < text.endIndex ? text.index(after: step1) : step1
        default:
            // Simple two-byte sequence
            return text.index(after: index)
        }
    }

    /// CSI: ESC [ <params> <final byte 0x40–0x7E>
    private static func skipCSI(in text: String, from start: String.Index) -> String.Index {
        var i = start
        while i < text.endIndex {
            let scalar = text[i].unicodeScalars.first?.value ?? 0
            i = text.index(after: i)
            if scalar >= 0x40 && scalar <= 0x7E { break }
        }
        return i
    }

    /// OSC: ESC ] <text> <BEL | ESC \>
    private static func skipOSC(in text: String, from start: String.Index) -> String.Index {
        var i = start
        while i < text.endIndex {
            let char = text[i]
            if char == "\u{07}" {
                return text.index(after: i)
            }
            if char == "\u{1B}" {
                let next = text.index(after: i)
                if next < text.endIndex && text[next] == "\\" {
                    return text.index(after: next)
                }
            }
            i = text.index(after: i)
        }
        return i
    }
}

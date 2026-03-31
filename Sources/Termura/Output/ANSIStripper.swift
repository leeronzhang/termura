import Foundation

/// Utility for stripping ANSI escape sequences from terminal output.
/// Covers CSI sequences (ESC[...m), OSC sequences, and other common escapes.
///
/// Implementation operates on the UTF-8 byte view throughout. ESC (0x1B) and all
/// ANSI control characters are single-byte ASCII, so grapheme-cluster iteration is
/// unnecessary and 4-8x slower on high-throughput PTY output.
enum ANSIStripper {
    // MARK: - Public API

    /// Strip all ANSI escape sequences from `text`.
    static func strip(_ text: String) -> String {
        let utf8 = text.utf8
        guard utf8.contains(0x1B) else { return text }

        var result = [UInt8]()
        result.reserveCapacity(utf8.count)
        var i = utf8.startIndex

        while i < utf8.endIndex {
            let byte = utf8[i]
            if byte == 0x1B {
                i = skipEscapeSequence(utf8: utf8, from: utf8.index(after: i))
            } else {
                result.append(byte)
                i = utf8.index(after: i)
            }
        }
        return String(bytes: result, encoding: .utf8) ?? text
    }

    // MARK: - Private helpers

    /// Advance past an escape sequence starting at `index` (the byte after ESC).
    private static func skipEscapeSequence(
        utf8: String.UTF8View,
        from index: String.UTF8View.Index
    ) -> String.UTF8View.Index {
        guard index < utf8.endIndex else { return index }
        let next = utf8[index]

        switch next {
        case UInt8(ascii: "["):
            return skipCSI(utf8: utf8, from: utf8.index(after: index))
        case UInt8(ascii: "]"):
            return skipOSC(utf8: utf8, from: utf8.index(after: index))
        case UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "*"), UInt8(ascii: "+"):
            // Designate character set — one extra byte
            let step1 = utf8.index(after: index)
            return step1 < utf8.endIndex ? utf8.index(after: step1) : step1
        default:
            // Simple two-byte sequence
            return utf8.index(after: index)
        }
    }

    /// CSI: ESC [ <params> <final byte 0x40-0x7E>
    private static func skipCSI(
        utf8: String.UTF8View,
        from start: String.UTF8View.Index
    ) -> String.UTF8View.Index {
        var i = start
        while i < utf8.endIndex {
            let byte = utf8[i]
            i = utf8.index(after: i)
            if byte >= 0x40 && byte <= 0x7E { break }
        }
        return i
    }

    /// OSC: ESC ] <text> <BEL | ESC \>
    private static func skipOSC(
        utf8: String.UTF8View,
        from start: String.UTF8View.Index
    ) -> String.UTF8View.Index {
        var i = start
        while i < utf8.endIndex {
            let byte = utf8[i]
            if byte == 0x07 { // BEL
                return utf8.index(after: i)
            }
            if byte == 0x1B { // ESC — ST terminator: ESC backslash
                let next = utf8.index(after: i)
                if next < utf8.endIndex && utf8[next] == UInt8(ascii: "\\") {
                    return utf8.index(after: next)
                }
            }
            i = utf8.index(after: i)
        }
        return i
    }
}

import Foundation

/// Utility for sanitizing terminal window titles.
///
/// Strips agent icon prefixes (Unicode symbols, multi-char sequences like ">_")
/// from OSC-reported terminal titles before they are stored or displayed.
///
/// Kept in the Session layer so SessionStore can apply sanitization without
/// depending on the Services layer (CLAUDE.md clean-architecture rule).
enum TitleSanitizer {

    /// Unicode symbols commonly used as status indicators in terminal titles.
    private static let symbolPrefixSet: CharacterSet = {
        CharacterSet(charactersIn:
            "\u{2733}\u{273B}\u{2731}" + // asterisks
            "\u{2726}\u{2605}\u{2606}" + // stars
            "\u{00B7}\u{2022}\u{2027}\u{2219}\u{22C5}\u{2024}\u{2981}" + // dots/bullets (standard)
            "\u{0387}\u{FF65}\u{30FB}\u{16EB}\u{1427}" + // dot look-alikes (Greek, halfwidth, katakana, runic, Canadian)
            "\u{25CF}\u{25CB}\u{25C9}\u{2B24}\u{2B58}\u{26AB}\u{26AA}" + // circles
            "\u{25AA}\u{25AB}\u{25C6}\u{25C7}" + // geometric
            "\u{203A}\u{276F}\u{2192}\u{26A1}" + // arrows/prompt
            "\u{2714}\u{2718}\u{23F3}" + // status
            "\u{2012}\u{2013}\u{2014}\u{2015}" + // dashes
            "\u{FEFF}\u{200B}\u{200C}\u{200D}\u{2060}\u{00AD}" // invisible/format chars
        )
    }()

    /// Returns true for non-ASCII Unicode scalars that belong to symbol or format categories
    /// and are therefore safe to strip as leading title prefixes. ASCII punctuation is excluded
    /// to avoid stripping legitimate characters like "." or "!" that may start a title.
    private static func isStrippableSymbolCategory(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value > 0x007F else { return false }
        switch scalar.properties.generalCategory {
        case .format, .otherSymbol, .mathSymbol, .modifierSymbol:
            return true
        case .otherPunctuation:
            // Strip non-ASCII "other punctuation" (covers dot look-alikes in any script).
            return true
        default:
            return false
        }
    }

    /// Strips known agent icon prefixes from OSC terminal titles.
    static func stripAgentPrefixes(_ title: String) -> String {
        var stripped = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let multiCharPrefixes = [">_"]
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in multiCharPrefixes where stripped.hasPrefix(prefix) {
                stripped = String(stripped.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
            if let firstChar = stripped.first,
               let firstScalar = firstChar.unicodeScalars.first,
               symbolPrefixSet.contains(firstScalar) || isStrippableSymbolCategory(firstScalar) {
                stripped = String(stripped.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }
        return stripped.isEmpty ? title : stripped
    }
}

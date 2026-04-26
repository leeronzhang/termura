import Foundation

/// Pulls wiki-link targets out of a note body. Shared between `BacklinkIndex`
/// (in-memory reverse map) and `FileBackedNoteRepository+Relations` (GRDB sync
/// of `note_links` rows) so the regex lives in one place.
public enum WikiLinkExtractor {
    /// `[[target]]` or `[[target|display]]` — captures `target`.
    public static let pattern = #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#

    /// Returns deduplicated target titles in source order. Case is preserved
    /// as-written; dedup is case-insensitive (so `[[Foo]]` and `[[foo]]` collapse
    /// to the first occurrence).
    public static func extract(from body: String) -> [String] {
        guard !body.isEmpty else { return [] }
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            // Non-critical: hard-coded pattern is invalid; skip silently and return no matches.
            return []
        }
        let nsBody = body as NSString
        let range = NSRange(location: 0, length: nsBody.length)
        var seen = Set<String>()
        var ordered: [String] = []
        for match in regex.matches(in: body, range: range) {
            guard match.numberOfRanges >= 2 else { continue }
            let target = nsBody.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespaces)
            guard !target.isEmpty, seen.insert(target.lowercased()).inserted else { continue }
            ordered.append(target)
        }
        return ordered
    }
}

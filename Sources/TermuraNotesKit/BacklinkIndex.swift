import Foundation

/// In-memory reverse index: given a note title, find all notes that link to it via `[[...]]`.
///
/// Rebuilt from the full notes array whenever notes are loaded or persisted.
/// File-as-truth — no GRDB storage needed.
public struct BacklinkIndex: Sendable {
    /// Lowercased target title → array of (id, title) of notes containing that link.
    private var reverseMap: [String: [(id: NoteID, title: String)]] = [:]

    public init() {}

    /// Scan every note body for `[[target]]` or `[[target|display]]` and build the reverse map.
    public mutating func rebuild(from notes: [NoteRecord]) {
        reverseMap.removeAll(keepingCapacity: true)
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: #"\[\[([^\]|]+)(?:\|[^\]]*)?\]\]"#)
        } catch {
            // Non-critical: if the hardcoded pattern is invalid the index stays empty.
            return
        }
        for note in notes {
            var seen = Set<String>()
            let nsBody = note.body as NSString
            let range = NSRange(location: 0, length: nsBody.length)
            for match in regex.matches(in: note.body, range: range) {
                guard match.numberOfRanges >= 2 else { continue }
                let target = nsBody.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)
                let key = target.lowercased()
                guard seen.insert(key).inserted else { continue }
                reverseMap[key, default: []].append((id: note.id, title: note.title))
            }
        }
    }

    /// Returns notes that contain a `[[title]]` link pointing to the given title.
    public func backlinks(for title: String) -> [(id: NoteID, title: String)] {
        reverseMap[title.lowercased()] ?? []
    }

    /// Number of unique target titles in the index.
    public var targetCount: Int { reverseMap.count }
}

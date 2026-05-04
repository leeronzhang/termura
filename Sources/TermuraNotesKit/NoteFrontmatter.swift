import Foundation

/// YAML frontmatter codec for Markdown note files.
/// Schema is fixed (6 fields), so hand-rolled key-value parsing suffices without external YAML dependency.
public enum NoteFrontmatter {
    private static let separator = "---"
    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static func formatDate(_ date: Date) -> String {
        makeISO8601Formatter().string(from: date)
    }

    private static func parseDate(_ string: String) -> Date? {
        makeISO8601Formatter().date(from: string)
    }

    // MARK: - Encode

    public struct EncodeInput: Sendable {
        public let id: NoteID
        public let title: String
        public let isFavorite: Bool
        public let tags: [String]
        public let references: [String]
        public let isFolder: Bool
        public let createdAt: Date
        public let updatedAt: Date
        public let body: String

        public init(id: NoteID, title: String, isFavorite: Bool, tags: [String],
                    references: [String], isFolder: Bool,
                    createdAt: Date, updatedAt: Date, body: String) {
            self.id = id; self.title = title; self.isFavorite = isFavorite
            self.tags = tags; self.references = references; self.isFolder = isFolder
            self.createdAt = createdAt; self.updatedAt = updatedAt; self.body = body
        }
    }

    public static func encode(_ input: EncodeInput) -> String {
        var lines = [separator]
        lines.append("id: \(input.id.rawValue.uuidString)")
        lines.append("title: \(escapeYAMLString(input.title))")
        lines.append("favorite: \(input.isFavorite)")
        if !input.tags.isEmpty {
            let joined = input.tags.map { escapeYAMLString($0) }.joined(separator: ", ")
            lines.append("tags: [\(joined)]")
        }
        if !input.references.isEmpty {
            let joined = input.references.map { escapeYAMLString($0) }.joined(separator: ", ")
            lines.append("references: [\(joined)]")
        }
        if input.isFolder {
            lines.append("folder: true")
        }
        lines.append("created: \(formatDate(input.createdAt))")
        lines.append("updated: \(formatDate(input.updatedAt))")
        lines.append(separator)
        lines.append(input.body)
        return lines.joined(separator: "\n")
    }

    public static func encode(record: NoteRecord) -> String {
        encode(EncodeInput(
            id: record.id, title: record.title, isFavorite: record.isFavorite,
            tags: record.tags, references: record.references, isFolder: record.isFolder,
            createdAt: record.createdAt, updatedAt: record.updatedAt,
            body: record.body
        ))
    }

    // MARK: - Decode

    public struct Decoded: Sendable, Equatable {
        public let id: NoteID
        public var title: String
        public var isFavorite: Bool
        public var tags: [String]
        public var references: [String]
        public var isFolder: Bool
        public var createdAt: Date
        public var updatedAt: Date
        public var body: String
    }

    public static func decode(from content: String) throws -> Decoded {
        let lines = content.components(separatedBy: "\n")
        guard let firstSep = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == separator }) else {
            throw NoteFileError.missingFrontmatter
        }
        let afterFirst = lines.index(after: firstSep)
        guard afterFirst < lines.endIndex,
              let secondSep = lines[afterFirst...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == separator })
        else {
            throw NoteFileError.missingFrontmatter
        }

        let frontmatterLines = lines[(firstSep + 1) ..< secondSep]
        let kvPairs = parseFrontmatterLines(Array(frontmatterLines))

        guard let idStr = kvPairs["id"], let uuid = UUID(uuidString: idStr) else {
            throw NoteFileError.missingRequiredField("id")
        }

        let title = kvPairs["title"] ?? ""
        let favorite = kvPairs["favorite"] == "true"
        let tags = parseStringArray(kvPairs["tags"])
        let references = parseStringArray(kvPairs["references"])
        let isFolder = kvPairs["folder"] == "true"

        let createdAt: Date = if let raw = kvPairs["created"], let parsed = parseDate(raw) {
            parsed
        } else {
            Date()
        }

        let updatedAt: Date = if let raw = kvPairs["updated"], let parsed = parseDate(raw) {
            parsed
        } else {
            Date()
        }

        let bodyStartIndex = lines.index(after: secondSep)
        let body: String = if bodyStartIndex < lines.endIndex {
            lines[bodyStartIndex...].joined(separator: "\n")
        } else {
            ""
        }

        return Decoded(
            id: NoteID(rawValue: uuid), title: title, isFavorite: favorite,
            tags: tags, references: references, isFolder: isFolder,
            createdAt: createdAt, updatedAt: updatedAt, body: body
        )
    }

    // MARK: - Private helpers

    private static func parseFrontmatterLines(_ lines: [String]) -> [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex ..< colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }

    /// Parses a YAML inline array of strings: `[a, "b with comma", c]`.
    /// Used for both `tags:` and `references:` fields.
    private static func parseStringArray(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        var trimmed = raw
        if trimmed.hasPrefix("[") { trimmed = String(trimmed.dropFirst()) }
        if trimmed.hasSuffix("]") { trimmed = String(trimmed.dropLast()) }
        return trimmed.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { unquote($0) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ string: String) -> String {
        guard string.hasPrefix("\"") && string.hasSuffix("\"") && string.count >= 2 else { return string }
        let inner = String(string.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func escapeYAMLString(_ string: String) -> String {
        if string.contains(":") || string.contains("#") || string.contains("\"") || string.contains("\n") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return string
    }
}

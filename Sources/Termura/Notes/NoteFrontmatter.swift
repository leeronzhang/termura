import Foundation

/// YAML frontmatter codec for Markdown note files.
/// Schema is fixed (6 fields), so hand-rolled key-value parsing suffices without external YAML dependency.
enum NoteFrontmatter {
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

    struct EncodeInput: Sendable {
        let id: NoteID
        let title: String
        let isFavorite: Bool
        let tags: [String]
        let references: [String]
        let createdAt: Date
        let updatedAt: Date
        let body: String
    }

    static func encode(_ input: EncodeInput) -> String {
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
        lines.append("created: \(formatDate(input.createdAt))")
        lines.append("updated: \(formatDate(input.updatedAt))")
        lines.append(separator)
        lines.append(input.body)
        return lines.joined(separator: "\n")
    }

    static func encode(record: NoteRecord) -> String {
        encode(EncodeInput(
            id: record.id, title: record.title, isFavorite: record.isFavorite,
            tags: [], references: record.references,
            createdAt: record.createdAt, updatedAt: record.updatedAt,
            body: record.body
        ))
    }

    // MARK: - Decode

    struct Decoded: Sendable, Equatable {
        let id: NoteID
        var title: String
        var isFavorite: Bool
        var tags: [String]
        var references: [String]
        var createdAt: Date
        var updatedAt: Date
        var body: String
    }

    static func decode(from content: String) throws -> Decoded {
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
            tags: tags, references: references,
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
        var s = raw
        if s.hasPrefix("[") { s = String(s.dropFirst()) }
        if s.hasSuffix("]") { s = String(s.dropLast()) }
        return s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { unquote($0) }
            .filter { !$0.isEmpty }
    }

    private static func unquote(_ s: String) -> String {
        guard s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 else { return s }
        let inner = String(s.dropFirst().dropLast())
        return inner.replacingOccurrences(of: "\\\"", with: "\"")
    }

    private static func escapeYAMLString(_ s: String) -> String {
        if s.contains(":") || s.contains("#") || s.contains("\"") || s.contains("\n") {
            let escaped = s.replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        return s
    }
}

// MARK: - Errors

enum NoteFileError: LocalizedError {
    case missingFrontmatter
    case missingRequiredField(String)
    case fileReadFailed(path: String, underlying: Error)
    case fileWriteFailed(path: String, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            "Note file is missing YAML frontmatter delimiters (---)."
        case let .missingRequiredField(field):
            "Note frontmatter is missing required field: \(field)"
        case let .fileReadFailed(path, underlying):
            "Failed to read note file at \(path): \(underlying.localizedDescription)"
        case let .fileWriteFailed(path, underlying):
            "Failed to write note file at \(path): \(underlying.localizedDescription)"
        }
    }
}

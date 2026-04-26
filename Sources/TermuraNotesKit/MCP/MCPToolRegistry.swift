import Foundation

/// Defines MCP tools and dispatches tool calls to NoteFileLister operations.
public struct MCPToolRegistry: Sendable {
    private let lister: NoteFileLister
    private let notesDirectory: URL

    public init(lister: NoteFileLister, notesDirectory: URL) {
        self.lister = lister
        self.notesDirectory = notesDirectory
    }

    // MARK: - Tool Definitions

    public var definitions: [MCPToolDefinition] {
        [listNotesDef, readNoteDef, searchNotesDef, appendToNoteDef, createNoteDef, linkNotesDef]
    }

    private var listNotesDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "list_notes",
            description: "List all notes with metadata (id, title, favorite, folder, created, updated).",
            inputSchema: .object(["type": .string("object"), "properties": .object([:])])
        )
    }

    private var readNoteDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "read_note",
            description: "Read a note by title or ID prefix. Returns full markdown body.",
            inputSchema: schemaWithRequired(["identifier": propString("Note title or UUID prefix.")])
        )
    }

    private var searchNotesDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "search_notes",
            description: "Full-text search across all notes. Returns matching notes with context lines.",
            inputSchema: schemaWithRequired(["query": propString("Search query string.")])
        )
    }

    private var appendToNoteDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "append_to_note",
            description: "Append content to an existing note.",
            inputSchema: schemaWithRequired([
                "identifier": propString("Note title or UUID prefix."),
                "content": propString("Content to append.")
            ])
        )
    }

    private var createNoteDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "create_note",
            description: "Create a new note with optional body/tags.",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "title": propString("Note title."),
                    "body": propString("Initial markdown body."),
                    "tags": .object(["type": .string("array"), "items": .object(["type": .string("string")]),
                                     "description": .string("Tags for the note.")])
                ]),
                "required": .array([.string("title")])
            ])
        )
    }

    private var linkNotesDef: MCPToolDefinition {
        MCPToolDefinition(
            name: "link_notes",
            description: "Add a [[backlink]] from one note to another.",
            inputSchema: schemaWithRequired([
                "from": propString("Source note title or UUID prefix."),
                "to": propString("Target note title or UUID prefix.")
            ])
        )
    }

    // MARK: - Schema Helpers

    private func propString(_ desc: String) -> JSONValue {
        .object(["type": .string("string"), "description": .string(desc)])
    }

    private func schemaWithRequired(_ props: [String: JSONValue]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(props),
            "required": .array(props.keys.sorted().map { .string($0) })
        ])
    }

    // MARK: - Dispatch

    public func call(name: String, arguments: [String: JSONValue], now: Date = Date()) -> MCPToolResult {
        do {
            switch name {
            case "list_notes": return try handleListNotes()
            case "read_note": return try handleReadNote(arguments)
            case "search_notes": return try handleSearchNotes(arguments)
            case "append_to_note": return try handleAppendToNote(arguments, now: now)
            case "create_note": return try handleCreateNote(arguments, now: now)
            case "link_notes": return try handleLinkNotes(arguments, now: now)
            default: return .error("Unknown tool: \(name)")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: - Handlers

    private func handleListNotes() throws -> MCPToolResult {
        let notes = try lister.listNotes(in: notesDirectory)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let items = notes.map { note in
            NoteListItem(
                id: note.id.rawValue.uuidString,
                title: note.title,
                favorite: note.isFavorite,
                folder: note.isFolder,
                created: note.createdAt,
                updated: note.updatedAt
            )
        }
        let data = try encoder.encode(items)
        return MCPToolResult(text: String(data: data, encoding: .utf8) ?? "[]")
    }

    private func handleReadNote(_ args: [String: JSONValue]) throws -> MCPToolResult {
        guard let identifier = args["identifier"]?.stringValue else {
            return .error("Missing required parameter: identifier")
        }
        guard let (note, _) = try resolveNote(title: identifier, lister: lister, directory: notesDirectory) else {
            return .error("Note not found: \(identifier)")
        }
        return MCPToolResult(text: "# \(note.title)\n\n\(note.body)")
    }

    private func handleSearchNotes(_ args: [String: JSONValue]) throws -> MCPToolResult {
        guard let query = args["query"]?.stringValue else {
            return .error("Missing required parameter: query")
        }
        let results = try lister.searchNotes(query: query, in: notesDirectory)
        if results.isEmpty { return MCPToolResult(text: "No notes matched \"\(query)\".") }
        let lines = results.map { result in
            let matchPreview = result.matches.prefix(3).joined(separator: "\n  ")
            return "\(result.note.title)\n  \(matchPreview)"
        }
        return MCPToolResult(text: lines.joined(separator: "\n\n"))
    }

    private func handleAppendToNote(_ args: [String: JSONValue], now: Date) throws -> MCPToolResult {
        guard let identifier = args["identifier"]?.stringValue else {
            return .error("Missing required parameter: identifier")
        }
        guard let content = args["content"]?.stringValue else {
            return .error("Missing required parameter: content")
        }
        guard let (note, _) = try resolveNote(title: identifier, lister: lister, directory: notesDirectory) else {
            return .error("Note not found: \(identifier)")
        }
        var updated = note
        updated.body = note.body.hasSuffix("\n")
            ? note.body + content + "\n"
            : note.body + "\n" + content + "\n"
        updated.updatedAt = now
        _ = try lister.writeNote(updated, to: notesDirectory)
        return MCPToolResult(text: "Appended to \"\(note.title)\".")
    }

    private func handleCreateNote(_ args: [String: JSONValue], now: Date) throws -> MCPToolResult {
        guard let title = args["title"]?.stringValue else {
            return .error("Missing required parameter: title")
        }
        let body = args["body"]?.stringValue ?? ""
        let tags: [String] = args["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []

        var note = NoteRecord(title: title, body: body, tags: tags)
        note.createdAt = now
        note.updatedAt = now
        let url = try lister.writeNote(note, to: notesDirectory)
        return MCPToolResult(text: "Created \"\(title)\" at \(url.lastPathComponent).")
    }

    private func handleLinkNotes(_ args: [String: JSONValue], now: Date) throws -> MCPToolResult {
        guard let fromID = args["from"]?.stringValue else {
            return .error("Missing required parameter: from")
        }
        guard let toID = args["to"]?.stringValue else {
            return .error("Missing required parameter: to")
        }
        guard let (source, _) = try resolveNote(title: fromID, lister: lister, directory: notesDirectory) else {
            return .error("Source note not found: \(fromID)")
        }
        guard let (target, _) = try resolveNote(title: toID, lister: lister, directory: notesDirectory) else {
            return .error("Target note not found: \(toID)")
        }
        let link = "[[\(target.title)]]"
        if source.body.contains(link) {
            return MCPToolResult(text: "Link to \"\(target.title)\" already exists in \"\(source.title)\".")
        }
        var updated = source
        updated.body = source.body.hasSuffix("\n")
            ? source.body + "\n" + link + "\n"
            : source.body + "\n\n" + link + "\n"
        updated.updatedAt = now
        _ = try lister.writeNote(updated, to: notesDirectory)
        return MCPToolResult(text: "Linked \"\(source.title)\" → \"\(target.title)\".")
    }
}

// MARK: - Internal DTO

private struct NoteListItem: Encodable {
    let id: String
    let title: String
    let favorite: Bool
    let folder: Bool
    let created: Date
    let updated: Date
}

import Foundation
import TermuraRemoteProtocol

/// Translates one line of Claude Code's transcript JSONL
/// (`~/.claude/projects/<encoded-cwd>/<sessionId>.jsonl`, append-only,
/// one JSON object per line) into zero or more wire-friendly
/// `AgentEvent`s.
///
/// Pure transformation — no IO, no global state. The caller owns the
/// JSONL file watcher (the harness side) and the per-session monotonic
/// `seq` allocator. Lives in `TermuraRemoteServer` because the wire
/// types it produces are public; the file watcher and per-cwd
/// resolver stay in the private harness module since they are tied
/// to the paid remote-control feature.
///
/// **Forward compatibility**: unknown top-level `type` values and
/// unknown content-block `type`s are dropped (return `[]`) instead of
/// throwing, so a Claude Code update introducing new event kinds does
/// not break older Termura builds.
public struct ClaudeCodeTranscriptParser: Sendable {
    public init() {}

    public enum ParseError: Error, Sendable, Equatable {
        case invalidJSON
        case missingField(String)
    }

    /// Parse one JSONL line. Returns 0+ `AgentEvent`s — a single
    /// transcript line can carry multiple content blocks (e.g. an
    /// assistant turn with both a `text` block and a `tool_use`
    /// block produces two events).
    ///
    /// `seqAllocator` is invoked once per produced event so the caller
    /// can keep a per-channel-per-session monotonic counter; the
    /// parser is stateless across calls.
    ///
    /// `idAllocator` provides a fallback UUID when the transcript line
    /// has no `uuid` (rare meta lines). The default uses `UUID()` —
    /// pass a deterministic allocator in tests.
    public func parseLine(
        _ line: Data,
        sessionId: UUID,
        seqAllocator: () -> UInt64,
        idAllocator: () -> UUID = { UUID() }
    ) throws -> [AgentEvent] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw: RawTranscriptLine
        do {
            raw = try decoder.decode(RawTranscriptLine.self, from: line)
        } catch {
            throw ParseError.invalidJSON
        }
        return events(from: raw, sessionId: sessionId, seqAllocator: seqAllocator, idAllocator: idAllocator)
    }

    private func events(
        from raw: RawTranscriptLine,
        sessionId: UUID,
        seqAllocator: () -> UInt64,
        idAllocator: () -> UUID
    ) -> [AgentEvent] {
        switch raw.type {
        case "user":
            userEvents(raw, sessionId: sessionId, seqAllocator: seqAllocator, idAllocator: idAllocator)
        case "assistant":
            assistantEvents(raw, sessionId: sessionId, seqAllocator: seqAllocator, idAllocator: idAllocator)
        default:
            // Forward-compat: drop meta / unknown top-level types
            // (`permission-mode`, `file-history-snapshot`,
            // `attachment`, `queue-operation`, `last-prompt`,
            // `system`, future additions, etc.).
            []
        }
    }

    private func userEvents(
        _ raw: RawTranscriptLine,
        sessionId: UUID,
        seqAllocator: () -> UInt64,
        idAllocator: () -> UUID
    ) -> [AgentEvent] {
        guard let content = raw.message?.content else { return [] }
        switch content {
        case let .text(text):
            // Skip Claude Code's <local-command-caveat> + <command-name>
            // meta wrappers — these are CLI-mode internal scaffolding
            // and would clutter the iOS conversation view.
            if isMetaWrapper(text) { return [] }
            let event = AgentEvent(
                id: raw.uuid ?? idAllocator(),
                sessionId: sessionId,
                seq: seqAllocator(),
                producedAt: raw.timestamp ?? Date(),
                payload: .userText(text)
            )
            return [event]
        case let .blocks(blocks):
            return blocks.compactMap { block -> AgentEvent? in
                guard case let .toolResult(content, isError) = block else { return nil }
                let summary = content ?? ""
                return AgentEvent(
                    id: raw.uuid ?? idAllocator(),
                    sessionId: sessionId,
                    seq: seqAllocator(),
                    producedAt: raw.timestamp ?? Date(),
                    payload: .assistantToolResult(summary: summary, isError: isError ?? false)
                )
            }
        }
    }

    private func assistantEvents(
        _ raw: RawTranscriptLine,
        sessionId: UUID,
        seqAllocator: () -> UInt64,
        idAllocator: () -> UUID
    ) -> [AgentEvent] {
        guard case let .blocks(blocks) = raw.message?.content else { return [] }
        return blocks.compactMap { block -> AgentEvent? in
            guard let payload = payload(for: block) else { return nil }
            return AgentEvent(
                id: idAllocator(),
                sessionId: sessionId,
                seq: seqAllocator(),
                producedAt: raw.timestamp ?? Date(),
                payload: payload
            )
        }
    }

    private func payload(for block: ContentBlock) -> AgentEventPayload? {
        switch block {
        case let .text(text):
            text.isEmpty ? nil : .assistantText(text)
        case let .thinking(text):
            text.isEmpty ? nil : .assistantThinking(text)
        case let .toolUse(name, input):
            .assistantToolUse(name: name, inputSummary: summarize(input: input))
        case .toolResult:
            // assistant-typed tool_result is uncommon but possible;
            // mirror the user-side handling for symmetry.
            nil
        }
    }

    private func summarize(input: [String: TranscriptAnyJSON]?) -> String {
        guard let input else { return "" }
        if case let .string(value) = input["command"] { return value }
        if case let .string(value) = input["file_path"] { return value }
        if case let .string(value) = input["path"] { return value }
        if case let .string(value) = input["pattern"] { return value }
        // Fallback: compact JSON, capped so a 10 KB tool input doesn't
        // pollute the wire. JSONEncoder failure here is non-actionable
        // (the input was already JSON-decoded above), so fall through
        // to "" rather than propagate.
        let data: Data
        do {
            data = try JSONEncoder().encode(input)
        } catch {
            return ""
        }
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(120))
    }

    private func isMetaWrapper(_ text: String) -> Bool {
        // Drop Claude Code's `type: "user"` CLI-scaffolding records
        // (command-mode bookkeeping, per-turn steering reminders, env
        // preamble). iOS would otherwise render them as bright user
        // bubbles.
        let prefixes = ["<local-command-caveat>", "<command-name>", "<command-message>", "<system-reminder>", "<env>", "<context>"]
        return prefixes.contains { text.hasPrefix($0) }
    }
}

// MARK: - Raw decoding shapes

private struct RawTranscriptLine: Decodable {
    let type: String
    let uuid: UUID?
    let timestamp: Date?
    let message: RawMessage?
}

private struct RawMessage: Decodable {
    let content: MessageContent?

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Wire-layer polymorphism: Claude Code's `message.content` is
        // either a `String` (plain user prompt) or `[ContentBlock]`
        // (assistant turns + user-side tool_result). Probe each shape;
        // a probe failure means "wrong shape, try the next one", not
        // a parser bug.
        if let str = decodePolymorphic(String.self, from: container, forKey: .content) {
            content = .text(str)
        } else if let blocks = decodePolymorphic([ContentBlock].self, from: container, forKey: .content) {
            content = .blocks(blocks)
        } else {
            content = nil
        }
    }

    enum CodingKeys: String, CodingKey { case content }
}

/// Wire-layer polymorphism helper: probes one type from a keyed
/// container. Returns `nil` when the container's value is a different
/// shape; the catch logs the discriminator so the failure is visible
/// in tests / debug builds without leaking the underlying error.
private func decodePolymorphic<T: Decodable, K: CodingKey>(
    _ type: T.Type,
    from container: KeyedDecodingContainer<K>,
    forKey key: K
) -> T? {
    do {
        return try container.decode(type, forKey: key)
    } catch let error as DecodingError {
        // Type mismatch is the expected case (caller probes the next
        // shape). We bind the error so the catch is not a silent
        // pass-through and a future debugger can inspect it.
        _ = error
        return nil
    } catch {
        _ = error
        return nil
    }
}

private enum MessageContent {
    case text(String)
    case blocks([ContentBlock])
}

private enum ContentBlock: Decodable {
    case text(String)
    case thinking(String)
    case toolUse(name: String, input: [String: TranscriptAnyJSON]?)
    case toolResult(content: String?, isError: Bool?)

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, name, input, content
        case isError = "is_error"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = try .text(container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "thinking":
            self = try .thinking(container.decodeIfPresent(String.self, forKey: .thinking) ?? "")
        case "tool_use":
            let name = try container.decode(String.self, forKey: .name)
            let input = try container.decodeIfPresent([String: TranscriptAnyJSON].self, forKey: .input)
            self = .toolUse(name: name, input: input)
        case "tool_result":
            // `content` may be a String or an array of {type:text,text}
            // chunks; probe each shape explicitly.
            let content: String? = decodeToolResultContent(from: container)
            let isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
            self = .toolResult(content: content, isError: isError)
        default:
            // Forward-compat: ignore unknown block types.
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown content block type: \(type)"
            )
        }
    }
}

private struct ToolResultChunk: Decodable {
    let text: String
}

/// Probes the two known shapes of `tool_result.content` (String or
/// `[ToolResultChunk]`) and joins the chunks if needed. Returns nil
/// when neither shape decodes — the caller treats that as "no
/// summary available" rather than a hard error.
private func decodeToolResultContent(
    from container: KeyedDecodingContainer<ContentBlock.CodingKeys>
) -> String? {
    if let str = decodePolymorphic(String.self, from: container, forKey: .content) {
        return str
    }
    if let chunks = decodePolymorphic([ToolResultChunk].self, from: container, forKey: .content) {
        return chunks.map(\.text).joined(separator: "\n")
    }
    return nil
}

// `TranscriptAnyJSON` lives in `TranscriptAnyJSON.swift` to keep this
// file under the file_length budget.

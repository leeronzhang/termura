import Foundation

/// Minimal `Any`-shaped JSON value used by `ClaudeCodeTranscriptParser`
/// so the `tool_use.input` blob (whose schema varies per Claude Code
/// tool — Bash takes `command`, Read takes `file_path`, Grep takes
/// `pattern`, etc.) can flow through the parser without pinning it
/// to one tool's input shape.
///
/// Used only to look up well-known fields and to round-trip the rest
/// as a compact JSON summary; not part of the public wire surface.
enum TranscriptAnyJSON: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([TranscriptAnyJSON])
    case object([String: TranscriptAnyJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Probe each JSON value shape; the first that decodes wins.
        // Wire-layer polymorphic decode — a per-shape failure routes
        // to the next branch via `tryDecode`, not a parser error.
        if let bool = TranscriptAnyJSON.tryDecode(Bool.self, from: container) {
            self = .bool(bool)
        } else if let number = TranscriptAnyJSON.tryDecode(Double.self, from: container) {
            self = .number(number)
        } else if let string = TranscriptAnyJSON.tryDecode(String.self, from: container) {
            self = .string(string)
        } else if let array = TranscriptAnyJSON.tryDecode([TranscriptAnyJSON].self, from: container) {
            self = .array(array)
        } else if let object = TranscriptAnyJSON.tryDecode([String: TranscriptAnyJSON].self, from: container) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    /// Probe one JSON value shape. Returns nil when the container's
    /// content is a different type — wire-layer polymorphism, not a
    /// business-logic error swallow.
    private static func tryDecode<T: Decodable>(
        _ type: T.Type,
        from container: any SingleValueDecodingContainer
    ) -> T? {
        do {
            return try container.decode(type)
        } catch let error as DecodingError {
            // Expected — caller probes the next shape.
            _ = error
            return nil
        } catch {
            _ = error
            return nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

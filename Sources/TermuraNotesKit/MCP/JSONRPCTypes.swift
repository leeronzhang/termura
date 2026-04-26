import Foundation

// MARK: - JSONValue

/// Type-safe representation of arbitrary JSON, used for JSON-RPC params/results.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        // Type probing: attempt each JSON type in order. DecodingError.typeMismatch
        // is expected when the value is a different type — catch and try the next.
        self = try Self.decodeBool(container)
            ?? Self.decodeInt(container)
            ?? Self.decodeDouble(container)
            ?? Self.decodeString(container)
            ?? Self.decodeArray(container)
            ?? Self.decodeObject(container)
            ?? { throw DecodingError.typeMismatch(
                JSONValue.self,
                .init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON type")
            ) }()
    }

    // Each probe catches typeMismatch and returns nil to allow the chain to continue.
    private static func decodeBool(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .bool(container.decode(Bool.self)) } catch { return nil }
    }

    private static func decodeInt(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .int(container.decode(Int.self)) } catch { return nil }
    }

    private static func decodeDouble(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .double(container.decode(Double.self)) } catch { return nil }
    }

    private static func decodeString(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .string(container.decode(String.self)) } catch { return nil }
    }

    private static func decodeArray(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .array(container.decode([JSONValue].self)) } catch { return nil }
    }

    private static func decodeObject(_ container: SingleValueDecodingContainer) -> JSONValue? {
        do { return try .object(container.decode([String: JSONValue].self)) } catch { return nil }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(val): try container.encode(val)
        case let .int(val): try container.encode(val)
        case let .double(val): try container.encode(val)
        case let .bool(val): try container.encode(val)
        case .null: try container.encodeNil()
        case let .array(val): try container.encode(val)
        case let .object(val): try container.encode(val)
        }
    }
}

public extension JSONValue {
    /// Extract string value or nil.
    var stringValue: String? {
        if case let .string(val) = self { return val }
        return nil
    }

    /// Extract object dictionary or nil.
    var objectValue: [String: JSONValue]? {
        if case let .object(val) = self { return val }
        return nil
    }

    /// Extract array or nil.
    var arrayValue: [JSONValue]? {
        if case let .array(val) = self { return val }
        return nil
    }

    /// Extract bool or nil.
    var boolValue: Bool? {
        if case let .bool(val) = self { return val }
        return nil
    }
}

// MARK: - JSON-RPC Request ID

/// JSON-RPC 2.0 request ID: either Int or String.
public enum JSONRPCRequestID: Sendable, Hashable {
    case int(Int)
    case string(String)
}

extension JSONRPCRequestID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Type probing: JSON-RPC ID is either Int or String.
        do {
            self = try .int(container.decode(Int.self))
        } catch {
            self = try .string(container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .int(val): try container.encode(val)
        case let .string(val): try container.encode(val)
        }
    }
}

// MARK: - JSON-RPC Messages

/// Incoming JSON-RPC 2.0 request or notification.
public struct JSONRPCRequest: Decodable, Sendable {
    public let jsonrpc: String
    public let id: JSONRPCRequestID?
    public let method: String
    public let params: JSONValue?
}

/// Outgoing JSON-RPC 2.0 success response.
public struct JSONRPCResponse: Encodable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: JSONRPCRequestID
    public let result: JSONValue

    public init(id: JSONRPCRequestID, result: JSONValue) {
        self.id = id
        self.result = result
    }
}

/// Outgoing JSON-RPC 2.0 error response.
public struct JSONRPCErrorResponse: Encodable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: JSONRPCRequestID?
    public let error: JSONRPCError

    public init(id: JSONRPCRequestID?, error: JSONRPCError) {
        self.id = id
        self.error = error
    }
}

/// JSON-RPC error object.
public struct JSONRPCError: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }

    public static let parseError = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid Request")
    public static let methodNotFound = JSONRPCError(code: -32601, message: "Method not found")
    public static let invalidParams = JSONRPCError(code: -32602, message: "Invalid params")
    public static func internalError(_ detail: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: detail)
    }
}

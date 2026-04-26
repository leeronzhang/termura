import Foundation

/// MCP protocol version supported by this server.
public let mcpProtocolVersion = "2024-11-05"

/// MCP tool definition returned by tools/list.
public struct MCPToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

extension MCPToolDefinition: Encodable {
    enum CodingKeys: String, CodingKey {
        case name, description, inputSchema
    }
}

/// A single content block in an MCP tool result.
public struct MCPContent: Encodable, Sendable {
    public let type: String
    public let text: String

    public init(text: String) {
        type = "text"
        self.text = text
    }
}

/// Result of an MCP tools/call invocation.
public struct MCPToolResult: Sendable {
    public let content: [MCPContent]
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        content = [MCPContent(text: text)]
        self.isError = isError
    }

    public static func error(_ message: String) -> MCPToolResult {
        MCPToolResult(text: message, isError: true)
    }
}

extension MCPToolResult: Encodable {
    enum CodingKeys: String, CodingKey {
        case content, isError
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        if isError {
            try container.encode(true, forKey: .isError)
        }
    }
}

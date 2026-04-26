import Foundation

/// MCP server: Content-Length framed JSON-RPC 2.0 over stdio.
/// OWNER: MCPCommand creates and runs this.
/// TEARDOWN: Returns when input yields nil (EOF).
public struct MCPServer: Sendable {
    private let registry: MCPToolRegistry
    private let serverName: String
    private let serverVersion: String

    public init(registry: MCPToolRegistry, name: String = "tn", version: String = "0.1.0") {
        self.registry = registry
        serverName = name
        serverVersion = version
    }

    // MARK: - Public Entry Points

    /// Run with injectable I/O (for testing).
    /// `readMessage` returns the next raw JSON message or nil on EOF.
    /// `writeMessage` emits a raw JSON response.
    public func run(
        readMessage: () throws -> Data?,
        writeMessage: (Data) throws -> Void
    ) throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        while let data = try readMessage() {
            let responseData: Data
            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: data)
                guard request.jsonrpc == "2.0" else {
                    let errResp = JSONRPCErrorResponse(id: request.id, error: .invalidRequest)
                    try writeMessage(encoder.encode(errResp))
                    continue
                }
                // Notifications (no id) get no response
                guard let requestID = request.id else {
                    _ = dispatch(request)
                    continue
                }
                let result = dispatch(request)
                let response = JSONRPCResponse(id: requestID, result: result)
                responseData = try encoder.encode(response)
            } catch {
                let errResp = JSONRPCErrorResponse(id: nil, error: .parseError)
                responseData = try encoder.encode(errResp)
            }
            try writeMessage(responseData)
        }
    }

    /// Run bound to stdin/stdout with Content-Length framing.
    public func runStdio() throws {
        try run(
            readMessage: { Self.readContentLengthMessage() },
            writeMessage: { data in Self.writeContentLengthMessage(data) }
        )
    }

    // MARK: - Method Dispatch

    private func dispatch(_ request: JSONRPCRequest) -> JSONValue {
        switch request.method {
        case "initialize":
            .object([
                "protocolVersion": .string(mcpProtocolVersion),
                "capabilities": .object(["tools": .object([:])]),
                "serverInfo": .object([
                    "name": .string(serverName),
                    "version": .string(serverVersion)
                ])
            ])

        case "notifications/initialized", "initialized":
            .null

        case "tools/list":
            encodeToolsList()

        case "tools/call":
            handleToolCall(request.params)

        default:
            .object([
                "error": .object([
                    "code": .int(JSONRPCError.methodNotFound.code),
                    "message": .string("Method not found: \(request.method)")
                ])
            ])
        }
    }

    private func encodeToolsList() -> JSONValue {
        let tools: [JSONValue] = registry.definitions.map { def in
            .object([
                "name": .string(def.name),
                "description": .string(def.description),
                "inputSchema": def.inputSchema
            ])
        }
        return .object(["tools": .array(tools)])
    }

    private func handleToolCall(_ params: JSONValue?) -> JSONValue {
        guard let obj = params?.objectValue,
              let name = obj["name"]?.stringValue else {
            return encodeToolResult(.error("Missing tool name in params."))
        }
        let arguments = obj["arguments"]?.objectValue ?? [:]
        let result = registry.call(name: name, arguments: arguments)
        return encodeToolResult(result)
    }

    private func encodeToolResult(_ result: MCPToolResult) -> JSONValue {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(result)
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            // Non-critical: fallback to a text error if encoding round-trip fails.
            return .object(["content": .array([
                .object(["type": .string("text"), "text": .string("encoding error: \(error.localizedDescription)")])
            ])])
        }
    }

    // MARK: - Content-Length Framing (stdio)

    /// Read one Content-Length-framed message from stdin. Returns nil on EOF.
    /// WHY: Uses FileHandle exclusively to avoid conflict between libc buffered I/O and raw fd reads.
    static func readContentLengthMessage() -> Data? {
        let handle = FileHandle.standardInput
        var contentLength: Int?

        // Read headers line by line until \r\n\r\n
        while true {
            let line = readHeaderLine(from: handle)
            guard let line else { return nil } // EOF
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { break }
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            if parts.count == 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
        }

        guard let length = contentLength, length > 0 else { return nil }

        var buffer = Data(capacity: length)
        while buffer.count < length {
            let chunk = handle.readData(ofLength: length - buffer.count)
            if chunk.isEmpty { return nil } // EOF
            buffer.append(chunk)
        }
        return buffer
    }

    /// Read a single line from a FileHandle, consuming up to and including \n.
    private static func readHeaderLine(from handle: FileHandle) -> String? {
        var bytes = Data()
        while true {
            let byte = handle.readData(ofLength: 1)
            if byte.isEmpty { return bytes.isEmpty ? nil : String(data: bytes, encoding: .utf8) }
            if byte[0] == UInt8(ascii: "\n") { break }
            bytes.append(byte)
        }
        return String(data: bytes, encoding: .utf8)
    }

    /// Write one Content-Length-framed message to stdout.
    static func writeContentLengthMessage(_ data: Data) {
        let header = "Content-Length: \(data.count)\r\n\r\n"
        FileHandle.standardOutput.write(Data(header.utf8))
        FileHandle.standardOutput.write(data)
    }
}

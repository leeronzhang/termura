import Foundation
@testable import TermuraNotesKit
import Testing

@Suite("MCPServer")
struct MCPServerTests {
    private func makeServer(tempDir: URL) -> MCPServer {
        let registry = MCPToolRegistry(lister: NoteFileLister(), notesDirectory: tempDir)
        return MCPServer(registry: registry)
    }

    private func roundTrip(server: MCPServer, request: [String: Any]) throws -> [String: Any] {
        let requestData = try JSONSerialization.data(withJSONObject: request)
        var response: Data?
        try server.run(
            readMessage: {
                if response == nil {
                    response = Data() // sentinel: first call returns request
                    return requestData
                }
                return nil // EOF on second call
            },
            writeMessage: { data in response = data }
        )
        guard let data = response else { throw TestError.noResponse }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    @Test("initialize returns protocol version and capabilities")
    func initialize() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let resp = try roundTrip(server: server, request: [
            "jsonrpc": "2.0", "id": 1, "method": "initialize", "params": ["capabilities": [:]] as [String: Any]
        ])

        let result = resp["result"] as? [String: Any]
        #expect(result?["protocolVersion"] as? String == "2024-11-05")
        let serverInfo = result?["serverInfo"] as? [String: Any]
        #expect(serverInfo?["name"] as? String == "termura-notes")
        let capabilities = result?["capabilities"] as? [String: Any]
        #expect(capabilities?["tools"] != nil)
    }

    @Test("tools/list returns all 6 tool definitions")
    func toolsList() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let resp = try roundTrip(server: server, request: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/list"
        ])

        let result = resp["result"] as? [String: Any]
        let tools = result?["tools"] as? [[String: Any]]
        #expect(tools?.count == 6)
        let names = Set(tools?.compactMap { $0["name"] as? String } ?? [])
        #expect(names.contains("list_notes"))
        #expect(names.contains("read_note"))
        #expect(names.contains("search_notes"))
        #expect(names.contains("append_to_note"))
        #expect(names.contains("create_note"))
        #expect(names.contains("link_notes"))
    }

    @Test("tools/call list_notes on empty directory")
    func listNotesEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let resp = try roundTrip(server: server, request: [
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "list_notes", "arguments": [:]] as [String: Any]
        ])

        let result = resp["result"] as? [String: Any]
        let content = result?["content"] as? [[String: Any]]
        let text = content?.first?["text"] as? String
        #expect(text == "[]")
    }

    @Test("unknown method returns method-not-found in result")
    func unknownMethod() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let resp = try roundTrip(server: server, request: [
            "jsonrpc": "2.0", "id": 4, "method": "nonexistent/method"
        ])

        let result = resp["result"] as? [String: Any]
        let error = result?["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32601)
    }

    @Test("malformed JSON returns parse error")
    func parseError() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let badData = Data("not json".utf8)
        var response: Data?
        try server.run(
            readMessage: {
                if response == nil {
                    response = Data()
                    return badData
                }
                return nil
            },
            writeMessage: { data in response = data }
        )
        let resp = try JSONSerialization.jsonObject(with: response!) as? [String: Any] ?? [:]
        let error = resp["error"] as? [String: Any]
        #expect(error?["code"] as? Int == -32700)
    }

    @Test("notification (no id) produces no response")
    func notification() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let server = makeServer(tempDir: tempDir)
        let notifData = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0", "method": "notifications/initialized"
        ])
        var responseWritten = false
        try server.run(
            readMessage: {
                if !responseWritten {
                    responseWritten = true
                    return notifData
                }
                return nil
            },
            writeMessage: { _ in
                // Should not be called for notifications
                #expect(Bool(false), "No response expected for notification")
            }
        )
    }
}

private enum TestError: Error {
    case noResponse
}

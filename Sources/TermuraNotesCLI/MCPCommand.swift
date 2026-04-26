import ArgumentParser
import Foundation
import TermuraNotesKit

struct MCPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp",
        abstract: "Start an MCP (Model Context Protocol) server over stdio."
    )

    func run() throws {
        let project = try ProjectDiscovery()
        try project.ensureDirectories()
        let registry = MCPToolRegistry(
            lister: NoteFileLister(),
            notesDirectory: project.notesDirectory
        )
        let server = MCPServer(registry: registry)
        // WHY: Stderr logging so stdout stays clean for JSON-RPC
        FileHandle.standardError.write(Data("tn MCP server started\n".utf8))
        try server.runStdio()
    }
}

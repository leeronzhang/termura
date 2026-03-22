import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "SessionExportService")

// MARK: - Protocol

protocol SessionExportProtocol: Actor {
    func exportHTML(session: SessionRecord, chunks: [OutputChunk]) async throws -> URL
    func exportJSON(session: SessionRecord, chunks: [OutputChunk]) async throws -> URL
}

// MARK: - Export Format

enum ExportFormat: String, Sendable, CaseIterable {
    case html
    case json
}

// MARK: - Implementation

actor SessionExportService: SessionExportProtocol {

    private let fileManager = FileManager.default

    private var exportDirectory: URL {
        let temp = fileManager.temporaryDirectory
        return temp.appendingPathComponent("termura-exports", isDirectory: true)
    }

    func exportHTML(session: SessionRecord, chunks: [OutputChunk]) async throws -> URL {
        try ensureExportDirectory()
        let html = HTMLRenderer.render(session: session, chunks: chunks)
        let fileName = sanitizeFileName(session.title) + ".html"
        let url = exportDirectory.appendingPathComponent(fileName)
        try html.write(to: url, atomically: true, encoding: .utf8)
        logger.info("Exported HTML: \(url.path)")
        return url
    }

    func exportJSON(session: SessionRecord, chunks: [OutputChunk]) async throws -> URL {
        try ensureExportDirectory()
        let export = JSONExportData(session: session, chunks: chunks)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let fileName = sanitizeFileName(session.title) + ".json"
        let url = exportDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        logger.info("Exported JSON: \(url.path)")
        return url
    }

    private func ensureExportDirectory() throws {
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let trimmed = String(safe.prefix(64))
        return trimmed.isEmpty ? "session" : trimmed
    }
}

// MARK: - JSON Export Model

private struct JSONExportData: Encodable {
    let version: String = "1.0"
    let exportedAt: Date
    let session: SessionData
    let chunks: [ChunkData]

    init(session: SessionRecord, chunks: [OutputChunk]) {
        exportedAt = Date()
        self.session = SessionData(record: session)
        self.chunks = chunks.prefix(AppConfig.Export.maxExportMessages).map { ChunkData(chunk: $0) }
    }

    struct SessionData: Encodable {
        let id: String
        let title: String
        let workingDirectory: String
        let createdAt: Date
        let branchType: String
        let parentID: String?

        init(record: SessionRecord) {
            id = record.id.rawValue.uuidString
            title = record.title
            workingDirectory = record.workingDirectory
            createdAt = record.createdAt
            branchType = record.branchType.rawValue
            parentID = record.parentID?.rawValue.uuidString
        }
    }

    struct ChunkData: Encodable {
        let id: String
        let command: String
        let contentType: String
        let output: [String]
        let exitCode: Int?
        let startedAt: Date
        let finishedAt: Date?
        let estimatedTokens: Int

        init(chunk: OutputChunk) {
            id = chunk.id.uuidString
            command = chunk.commandText
            contentType = chunk.contentType.rawValue
            output = chunk.outputLines
            exitCode = chunk.exitCode
            startedAt = chunk.startedAt
            finishedAt = chunk.finishedAt
            estimatedTokens = chunk.estimatedTokens
        }
    }
}

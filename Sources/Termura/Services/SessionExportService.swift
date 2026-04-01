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
    private let fileManager: any FileManagerProtocol
    private let clock: any AppClock

    init(fileManager: any FileManagerProtocol = FileManager.default, clock: any AppClock = LiveClock()) {
        self.fileManager = fileManager
        self.clock = clock
    }

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
        rotateOldExports()
        logger.info("Exported HTML: \(url.path)")
        return url
    }

    func exportJSON(session: SessionRecord, chunks: [OutputChunk]) async throws -> URL {
        try ensureExportDirectory()
        let export = JSONExportData(session: session, chunks: chunks, exportedAt: clock.now())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(export)
        let fileName = sanitizeFileName(session.title) + ".json"
        let url = exportDirectory.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
        rotateOldExports()
        logger.info("Exported JSON: \(url.path)")
        return url
    }

    private func ensureExportDirectory() throws {
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
    }

    /// Keeps the most recent `AppConfig.Export.maxRetainedExports` files; deletes the oldest.
    /// Called after a successful export so the directory does not grow without bound.
    /// Rotation is best-effort: individual delete failures are logged and skipped.
    private func rotateOldExports() {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: exportDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            logger.debug("ExportService: could not list exports directory: \(error.localizedDescription)")
            return
        }

        let sorted = contents.sorted { lhs, rhs in
            let lDate = modificationDate(of: lhs)
            let rDate = modificationDate(of: rhs)
            return lDate < rDate
        }
        let excess = sorted.count - AppConfig.Export.maxRetainedExports
        guard excess > 0 else { return }
        for url in sorted.prefix(excess) {
            do {
                try fileManager.removeItem(atPath: url.path)
                logger.debug("ExportService rotated old export: \(url.lastPathComponent)")
            } catch {
                logger.debug("ExportService could not rotate \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Returns the modification date of a file URL, or `.distantPast` if unavailable.
    /// Extracted as a helper so the sort comparator in `rotateOldExports` uses explicit do-catch.
    private func modificationDate(of url: URL) -> Date {
        do {
            return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast
        } catch {
            logger.debug("ExportService: could not read modification date for \(url.lastPathComponent): \(error.localizedDescription)")
            return .distantPast
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

    init(session: SessionRecord, chunks: [OutputChunk], exportedAt: Date) {
        self.exportedAt = exportedAt
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
            workingDirectory = record.workingDirectory ?? ""
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

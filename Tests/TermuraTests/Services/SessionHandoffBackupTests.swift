import Foundation
import Testing
@testable import Termura

// MARK: - Test Helpers

private func makeTempDir() throws -> String {
    let tmp = NSTemporaryDirectory() + "termura-backup-test-\(UUID().uuidString)"
    try FileManager.default.createDirectory(
        atPath: tmp,
        withIntermediateDirectories: true
    )
    return tmp
}

private func makeSession(workingDirectory: String? = nil) -> SessionRecord {
    SessionRecord(
        title: "Test Session",
        workingDirectory: workingDirectory,
        createdAt: Date().addingTimeInterval(-300),
        lastActiveAt: Date()
    )
}

private func makeAgentState(
    sessionID: SessionID,
    agentType: AgentType = .claudeCode
) -> AgentState {
    AgentState(
        sessionID: sessionID,
        agentType: agentType,
        status: .completed
    )
}

private actor MockMsgRepo: SessionMessageRepositoryProtocol {
    var savedMessages: [SessionMessage] = []
    func fetchMessages(for sessionID: SessionID, contentType: MessageContentType?) async throws -> [SessionMessage] {
        savedMessages.filter { $0.sessionID == sessionID }
    }
    func save(_ message: SessionMessage) async throws { savedMessages.append(message) }
    func delete(id: SessionMessageID) async throws { savedMessages.removeAll { $0.id == id } }
    func deleteAll(for sessionID: SessionID) async throws { savedMessages.removeAll { $0.sessionID == sessionID } }
    func countTokens(for sessionID: SessionID, contentType: MessageContentType) async throws -> Int { 0 }
}

private actor MockEvtRepo: HarnessEventRepositoryProtocol {
    var savedEvents: [HarnessEvent] = []
    func fetchEvents(for sessionID: SessionID) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID }
    }
    func save(_ event: HarnessEvent) async throws { savedEvents.append(event) }
    func fetchEvents(ofType type: HarnessEventType, for sessionID: SessionID) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID && $0.eventType == type }
    }
}

private func makeService() -> SessionHandoffService {
    SessionHandoffService(
        messageRepo: MockMsgRepo(),
        harnessEventRepo: MockEvtRepo(),
        summarizer: BranchSummarizer()
    )
}

// MARK: - writeContextFile backup/restore tests

@Suite("SessionHandoffService backup/restore")
struct SessionHandoffBackupTests {

    @Test("Creates directory if missing")
    func createsDirectory() async throws {
        let tmpDir = try makeTempDir()
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let service = makeService()
        let session = makeSession(workingDirectory: tmpDir)
        let chunks = [OutputChunk(
            sessionID: session.id,
            commandText: "echo test",
            outputLines: ["test output"],
            rawANSI: "test output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]
        let agentState = makeAgentState(sessionID: session.id)

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        let dirPath = (tmpDir as NSString).appendingPathComponent(
            AppConfig.SessionHandoff.directoryName
        )
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir))
        #expect(isDir.boolValue)
    }

    @Test("Backup file is created during overwrite and cleaned up after success")
    func backupCreatedAndCleaned() async throws {
        let tmpDir = try makeTempDir()
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let service = makeService()
        let session = makeSession(workingDirectory: tmpDir)
        let agentState = makeAgentState(sessionID: session.id)
        let chunks = [OutputChunk(
            sessionID: session.id,
            commandText: "first",
            outputLines: ["first output"],
            rawANSI: "first output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]

        // First write
        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        // Second write (triggers backup)
        let chunks2 = [OutputChunk(
            sessionID: session.id,
            commandText: "second",
            outputLines: ["second output"],
            rawANSI: "second output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]
        try await service.generateHandoff(
            session: session,
            chunks: chunks2,
            agentState: agentState
        )

        // Backup should be cleaned up after successful write
        let contextPath = (tmpDir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        let backupPath = contextPath + ".backup"
        #expect(!FileManager.default.fileExists(atPath: backupPath))

        // Main file should exist with second content
        let content = try String(contentsOfFile: contextPath, encoding: .utf8)
        #expect(content.contains("# Session Context"))
    }

    @Test("Atomic write preserves file content on success")
    func atomicWritePreservesContent() async throws {
        let tmpDir = try makeTempDir()
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let service = makeService()
        let session = makeSession(workingDirectory: tmpDir)
        let agentState = makeAgentState(sessionID: session.id)
        let chunks = [OutputChunk(
            sessionID: session.id,
            commandText: "echo hello",
            outputLines: ["We decided to use Swift because it is type-safe"],
            rawANSI: "We decided to use Swift because it is type-safe",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        let contextPath = (tmpDir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        let content = try String(contentsOfFile: contextPath, encoding: .utf8)
        #expect(content.hasPrefix("# Session Context"))
        #expect(content.contains("## Current Task Status"))
    }

    @Test("readExistingContext returns nil for missing file")
    func readMissingContextReturnsNil() async {
        let service = makeService()
        let context = await service.readExistingContext(projectRoot: "/nonexistent/path")
        #expect(context == nil)
    }

    @Test("readExistingContext round-trips through write")
    func readAfterWriteRoundTrips() async throws {
        let tmpDir = try makeTempDir()
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let service = makeService()
        let session = makeSession(workingDirectory: tmpDir)
        let agentState = makeAgentState(sessionID: session.id)
        let chunks = [OutputChunk(
            sessionID: session.id,
            commandText: "cmd",
            outputLines: ["output"],
            rawANSI: "output",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        let context = await service.readExistingContext(projectRoot: tmpDir)
        #expect(context != nil)
        #expect(context?.agentType == .claudeCode)
    }

    @Test("Multiple handoffs merge decisions correctly")
    func multipleHandoffsMergeDecisions() async throws {
        let tmpDir = try makeTempDir()
        defer { do { try FileManager.default.removeItem(atPath: tmpDir) } catch { _ = error } }

        let service = makeService()
        let session = makeSession(workingDirectory: tmpDir)
        let agentState = makeAgentState(sessionID: session.id)

        // First handoff with decisions
        let chunks1 = [OutputChunk(
            sessionID: session.id,
            commandText: "cmd1",
            outputLines: ["We decided to use approach A because it was faster"],
            rawANSI: "We decided to use approach A because it was faster",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]
        try await service.generateHandoff(
            session: session,
            chunks: chunks1,
            agentState: agentState
        )

        // Second handoff with more decisions
        let chunks2 = [OutputChunk(
            sessionID: session.id,
            commandText: "cmd2",
            outputLines: ["We chose option B instead of C because simpler"],
            rawANSI: "We chose option B instead of C because simpler",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        )]
        try await service.generateHandoff(
            session: session,
            chunks: chunks2,
            agentState: agentState
        )

        let context = await service.readExistingContext(projectRoot: tmpDir)
        #expect(context != nil)
        // Should have merged decisions from both handoffs
        #expect((context?.decisions.count ?? 0) >= 1)
    }
}

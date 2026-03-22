import Foundation
import Testing
@testable import Termura

// MARK: - Mock Repositories

private actor MockMessageRepo: SessionMessageRepositoryProtocol {
    var savedMessages: [SessionMessage] = []

    func fetchMessages(
        for sessionID: SessionID,
        contentType: MessageContentType?
    ) async throws -> [SessionMessage] {
        savedMessages.filter { $0.sessionID == sessionID }
    }

    func save(_ message: SessionMessage) async throws {
        savedMessages.append(message)
    }

    func delete(id: SessionMessageID) async throws {
        savedMessages.removeAll { $0.id == id }
    }

    func deleteAll(for sessionID: SessionID) async throws {
        savedMessages.removeAll { $0.sessionID == sessionID }
    }

    func countTokens(
        for sessionID: SessionID,
        contentType: MessageContentType
    ) async throws -> Int {
        savedMessages
            .filter { $0.sessionID == sessionID && $0.contentType == contentType }
            .reduce(0) { $0 + $1.tokenCount }
    }
}

private actor MockHarnessEventRepo: HarnessEventRepositoryProtocol {
    var savedEvents: [HarnessEvent] = []

    func fetchEvents(for sessionID: SessionID) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID }
    }

    func save(_ event: HarnessEvent) async throws {
        savedEvents.append(event)
    }

    func fetchEvents(
        ofType type: HarnessEventType,
        for sessionID: SessionID
    ) async throws -> [HarnessEvent] {
        savedEvents.filter { $0.sessionID == sessionID && $0.eventType == type }
    }
}

// MARK: - Test Helpers

private func makeTempDir() throws -> String {
    let tmp = NSTemporaryDirectory() + "termura-handoff-test-\(UUID().uuidString)"
    try FileManager.default.createDirectory(
        atPath: tmp,
        withIntermediateDirectories: true
    )
    return tmp
}

private func makeSession(workingDirectory: String = "") -> SessionRecord {
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

private func makeChunks(
    sessionID: SessionID,
    count: Int = 3,
    includeErrors: Bool = false
) -> [OutputChunk] {
    var chunks: [OutputChunk] = []
    for i in 0..<count {
        chunks.append(OutputChunk(
            sessionID: sessionID,
            commandText: "command-\(i)",
            outputLines: ["output line \(i)"],
            rawANSI: "output line \(i)",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date()
        ))
    }
    if includeErrors {
        chunks.append(OutputChunk(
            sessionID: sessionID,
            commandText: "failing-cmd",
            outputLines: ["error: something failed", "fatal: cannot proceed"],
            rawANSI: "error: something failed\nfatal: cannot proceed",
            exitCode: 1,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: .error
        ))
    }
    return chunks
}

private func makeService() -> (
    SessionHandoffService,
    MockMessageRepo,
    MockHarnessEventRepo
) {
    let msgRepo = MockMessageRepo()
    let eventRepo = MockHarnessEventRepo()
    let summarizer = BranchSummarizer()
    let service = SessionHandoffService(
        messageRepo: msgRepo,
        harnessEventRepo: eventRepo,
        summarizer: summarizer
    )
    return (service, msgRepo, eventRepo)
}

// MARK: - Tests

@Suite("SessionHandoffService")
struct SessionHandoffServiceTests {

    @Test("Generates handoff and writes context.md")
    func generateHandoff() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let session = makeSession(workingDirectory: tmpDir)
        let chunks = makeChunks(sessionID: session.id)
        let agentState = makeAgentState(sessionID: session.id)
        let (service, msgRepo, eventRepo) = makeService()

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        // Verify file was written
        let contextPath = (tmpDir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        let content = try String(contentsOfFile: contextPath, encoding: .utf8)
        #expect(content.contains("# Session Context"))
        #expect(content.contains("## Current Task Status"))
        #expect(content.contains("claudeCode"))

        // Verify metadata message saved
        let messages = await msgRepo.savedMessages
        #expect(messages.count == 1)
        #expect(messages.first?.contentType == .metadata)

        // Verify harness event saved
        let events = await eventRepo.savedEvents
        #expect(events.count == 1)
        #expect(events.first?.eventType == .sessionHandoff)
    }

    @Test("Does not generate handoff for empty workingDirectory")
    func emptyWorkingDirectory() async throws {
        let session = makeSession(workingDirectory: "")
        let chunks = makeChunks(sessionID: session.id)
        let agentState = makeAgentState(sessionID: session.id)
        let (service, msgRepo, _) = makeService()

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        let messages = await msgRepo.savedMessages
        #expect(messages.isEmpty)
    }

    @Test("Merges with existing context — taskStatus overwritten, decisions appended")
    func mergeExistingContext() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        // Write initial context
        let session = makeSession(workingDirectory: tmpDir)
        let chunks1 = makeChunks(sessionID: session.id, count: 2)
        let agentState = makeAgentState(sessionID: session.id)
        let (service, _, _) = makeService()

        try await service.generateHandoff(
            session: session,
            chunks: chunks1,
            agentState: agentState
        )

        // Write second handoff with different chunks
        let chunks2: [OutputChunk] = [
            OutputChunk(
                sessionID: session.id,
                commandText: "new-cmd",
                outputLines: ["We decided to use approach B because it was simpler"],
                rawANSI: "We decided to use approach B because it was simpler",
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
        ]

        try await service.generateHandoff(
            session: session,
            chunks: chunks2,
            agentState: agentState
        )

        // Verify file exists and has new task status
        let contextPath = (tmpDir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        let content = try String(contentsOfFile: contextPath, encoding: .utf8)
        #expect(content.contains("## Current Task Status"))
        // The second handoff has 1 command, so task status reflects that
        #expect(content.contains("1 command"))
    }

    @Test("Decisions are trimmed to maxDecisionEntries")
    func decisionsTrimmed() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let session = makeSession(workingDirectory: tmpDir)
        let agentState = makeAgentState(sessionID: session.id)
        let (service, _, _) = makeService()

        // Generate many handoffs to accumulate decisions
        for i in 0..<60 {
            let chunk = OutputChunk(
                sessionID: session.id,
                commandText: "cmd-\(i)",
                outputLines: ["We decided to use approach \(i) because reasons"],
                rawANSI: "We decided to use approach \(i) because reasons",
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
            try await service.generateHandoff(
                session: session,
                chunks: [chunk],
                agentState: agentState
            )
        }

        // Read back and count decisions
        let context = await service.readExistingContext(projectRoot: tmpDir)
        #expect(context != nil)
        let count = context?.decisions.count ?? 0
        #expect(count <= AppConfig.SessionHandoff.maxDecisionEntries)
    }

    @Test("Errors are extracted from error chunks")
    func errorExtraction() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let session = makeSession(workingDirectory: tmpDir)
        let chunks = makeChunks(
            sessionID: session.id,
            count: 1,
            includeErrors: true
        )
        let agentState = makeAgentState(sessionID: session.id)
        let (service, _, _) = makeService()

        try await service.generateHandoff(
            session: session,
            chunks: chunks,
            agentState: agentState
        )

        let contextPath = (tmpDir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        let content = try String(contentsOfFile: contextPath, encoding: .utf8)
        #expect(content.contains("## Key Errors Encountered"))
        #expect(content.contains("something failed"))
    }

    @Test("Context file is valid markdown with expected sections")
    func markdownFormat() async throws {
        let tmpDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let session = makeSession(workingDirectory: tmpDir)
        let chunks = makeChunks(sessionID: session.id, includeErrors: true)
        let agentState = makeAgentState(sessionID: session.id)
        let (service, _, _) = makeService()

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
        #expect(content.contains("> Last updated:"))
        #expect(content.contains("## Current Task Status"))
    }
}

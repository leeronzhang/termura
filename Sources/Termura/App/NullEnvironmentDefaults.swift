import Foundation

// Null objects used exclusively by EnvironmentKey.defaultValue in Release builds.
//
// Background: SwiftUI evaluates EnvironmentKey.defaultValue during attribute graph
// construction when applying .environment(...) modifiers — even when a real value is
// injected by an ancestor. This happens at every app launch on macOS 14+ / SwiftUI 7+.
// Using preconditionFailure in defaultValue therefore always crashes in Release.
//
// These null objects are NEVER reachable from live code. Production always injects
// real instances via ContentView / VisorWindowController .environment(...) calls.
// They exist solely so SwiftUI can complete its internal graph setup without crashing.

// MARK: - Notes

actor NullNoteRepository: NoteRepositoryProtocol {
    func fetchAll() async throws -> [NoteRecord] { [] }
    func save(_ note: NoteRecord) async throws {}
    func delete(id: NoteID) async throws {}
    func search(query: String) async throws -> [NoteRecord] { [] }
}

// MARK: - Session

actor NullSessionRepository: SessionRepositoryProtocol {
    func fetchAll() async throws -> [SessionRecord] { [] }
    func fetch(id: SessionID) async throws -> SessionRecord? { nil }
    func save(_ record: SessionRecord) async throws {}
    func delete(id: SessionID) async throws {}
    func archive(id: SessionID) async throws {}
    func search(query: String) async throws -> [SessionRecord] { [] }
    func reorder(ids: [SessionID]) async throws {}
    func setColorLabel(id: SessionID, label: SessionColorLabel) async throws {}
    func setPinned(id: SessionID, pinned: Bool) async throws {}
    func markEnded(id: SessionID, at date: Date) async throws {}
    func markReopened(id: SessionID) async throws {}
    func fetchChildren(of parentID: SessionID) async throws -> [SessionRecord] { [] }
    func fetchAncestors(of sessionID: SessionID) async throws -> [SessionRecord] { [] }
    func createBranch(from parentID: SessionID, type: BranchType, title: String) async throws -> SessionRecord {
        SessionRecord(title: title, workingDirectory: nil, parentID: parentID, branchType: type)
    }

    func updateSummary(_ sessionID: SessionID, summary: String) async throws {}
}

// MARK: - Search

actor NullSearchService: SearchServiceProtocol {
    func search(query: String) async throws -> SearchResults { .empty }
}

// MARK: - Session Messages

actor NullSessionMessageRepository: SessionMessageRepositoryProtocol {
    func fetchMessages(for sessionID: SessionID, contentType: MessageContentType?) async throws -> [SessionMessage] { [] }
    func save(_ message: SessionMessage) async throws {}
    func delete(id: SessionMessageID) async throws {}
    func deleteAll(for sessionID: SessionID) async throws {}
    func countTokens(for sessionID: SessionID, contentType: MessageContentType) async throws -> Int { 0 }
}

// MARK: - Git

struct NullGitService: GitServiceProtocol {
    func status(at directory: String) async throws -> GitStatusResult { .notARepo }
    func diff(file: String, staged: Bool, at directory: String) async throws -> String { "" }
    func trackedFiles(at directory: String) async throws -> Set<String> { [] }
    func showFile(at path: String, directory: String) async throws -> String { "" }
    func numstat(at directory: String) async throws -> [DiffStat] { [] }
}

// MARK: - File Tree

actor NullFileTreeService: FileTreeServiceProtocol {
    func scan(at projectRoot: String) -> [FileTreeNode] { [] }
    func annotate(tree: [FileTreeNode], with gitResult: GitStatusResult, trackedFiles: Set<String>) -> [FileTreeNode] { tree }
}

// MARK: - Token Counting

actor NullTokenCountingService: TokenCountingServiceProtocol {
    func accumulateInput(for sessionID: SessionID, text: String) {}
    func accumulateOutput(for sessionID: SessionID, text: String) {}
    func accumulateCached(for sessionID: SessionID, count: Int) {}
    func estimatedTokens(for sessionID: SessionID) -> Int { 0 }
    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown {
        TokenEstimateBreakdown(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
    }

    func applyParsedStats(for sessionID: SessionID, inputTokens: Int, outputTokens: Int, cachedTokens: Int) {}
    func reset(for sessionID: SessionID) {}
}

// MARK: - Context Injection

actor NullContextInjectionService: ContextInjectionServiceProtocol {
    func buildInjectionText(projectRoot: String) async -> String? { nil }
}

// MARK: - Session Handoff

actor NullSessionHandoffService: SessionHandoffServiceProtocol {
    func generateHandoff(session: SessionRecord, chunks: [OutputChunk], agentState: AgentState, projectRoot: String) async throws {}
    func readExistingContext(projectRoot: String) async -> HandoffContext? { nil }
}

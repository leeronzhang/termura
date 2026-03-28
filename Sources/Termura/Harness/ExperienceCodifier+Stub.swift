// HARNESS_ENABLED=1 is set in project.yml for the private (paid) build.
// When that flag is absent, this stub compiles in its place.
// The private package provides the real ExperienceCodifier with full functionality.

#if !HARNESS_ENABLED
actor ExperienceCodifier {
    init(harnessEventRepo: any HarnessEventRepositoryProtocol) {}

    func generateDraft(from chunk: OutputChunk) -> RuleDraft {
        RuleDraft(
            errorChunkID: chunk.id,
            sessionID: chunk.sessionID,
            suggestedRule: "",
            errorSummary: ErrorSummary(title: "", context: "", antiPattern: "", suggestion: "")
        )
    }

    func appendRule(draft: RuleDraft, to filePath: String, sessionID: SessionID) async throws {}
}
#endif

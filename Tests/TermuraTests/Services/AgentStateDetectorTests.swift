import Testing
@testable import Termura

@Suite("AgentStateDetector")
struct AgentStateDetectorTests {

    private func makeDetector() -> AgentStateDetector {
        AgentStateDetector(sessionID: SessionID())
    }

    // MARK: - Command Detection

    @Test("Detects claude command as claudeCode")
    func detectClaude() async {
        let detector = makeDetector()
        let type = await detector.detectFromCommand("claude")
        #expect(type == .claudeCode)
    }

    @Test("Detects codex command")
    func detectCodex() async {
        let detector = makeDetector()
        let type = await detector.detectFromCommand("codex --model o4-mini")
        #expect(type == .codex)
    }

    @Test("Detects aider command")
    func detectAider() async {
        let detector = makeDetector()
        let type = await detector.detectFromCommand("aider --model sonnet")
        #expect(type == .aider)
    }

    @Test("Returns nil for unknown command")
    func detectUnknown() async {
        let detector = makeDetector()
        let type = await detector.detectFromCommand("ls -la")
        #expect(type == nil)
    }

    // MARK: - Output Analysis

    @Test("Detects waiting input from prompt")
    func detectWaitingInput() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let status = await detector.analyzeOutput("Some output\n> ")
        #expect(status == .waitingInput)
    }

    @Test("Detects error status")
    func detectError() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let status = await detector.analyzeOutput("API error: rate limit exceeded")
        #expect(status == .error)
    }

    @Test("Detects tool running")
    func detectToolRunning() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let status = await detector.analyzeOutput("⏺ Writing to file.swift")
        #expect(status == .toolRunning)
    }

    @Test("Returns idle when no agent detected")
    func idleWithoutAgent() async {
        let detector = makeDetector()
        let status = await detector.analyzeOutput("some random output")
        #expect(status == .idle)
    }

    // MARK: - Build State

    @Test("buildState returns nil without detection")
    func buildStateNil() async {
        let detector = makeDetector()
        let state = await detector.buildState()
        #expect(state == nil)
    }

    @Test("buildState returns state after detection")
    func buildStateAfterDetect() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let state = await detector.buildState()
        #expect(state != nil)
        #expect(state?.agentType == .claudeCode)
    }
}

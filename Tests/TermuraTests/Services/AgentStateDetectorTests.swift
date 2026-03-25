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

    // MARK: - Extended Agent Type Detection

    @Test("Detects opencode command")
    func detectOpenCode() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("opencode start") == .openCode)
    }

    @Test("Detects oc shorthand as openCode")
    func detectOCShorthand() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("oc run") == .openCode)
    }

    @Test("Detects gemini command")
    func detectGemini() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("gemini chat") == .gemini)
    }

    @Test("Detects pi command")
    func detectPi() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("pi run") == .pi)
    }

    @Test("Detects pi-agent command")
    func detectPiAgent() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("pi-agent start") == .pi)
    }

    @Test("Case insensitive command detection")
    func detectCaseInsensitive() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("CLAUDE code") == .claudeCode)
    }

    @Test("Path prefix detection: /usr/local/bin/claude")
    func detectPathPrefix() async {
        let detector = makeDetector()
        #expect(await detector.detectFromCommand("/usr/local/bin/claude") == .claudeCode)
    }

    // MARK: - Status Transitions

    @Test("Detects thinking status from output")
    func detectThinking() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let status = await detector.analyzeOutput("Thinking\u{2026}")
        #expect(status == .thinking)
    }

    @Test("Detects completed status from output")
    func detectCompleted() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        let status = await detector.analyzeOutput("Task completed successfully")
        #expect(status == .completed)
    }

    @Test("Reset clears detected state")
    func resetClearsState() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")
        await detector.reset()
        #expect(await detector.buildState() == nil)
    }

    @Test("Status transition sequence: thinking -> toolRunning -> completed")
    func statusTransitionSequence() async {
        let detector = makeDetector()
        _ = await detector.detectFromCommand("claude")

        let thinking = await detector.analyzeOutput("Thinking\u{2026}")
        #expect(thinking == .thinking)

        let running = await detector.analyzeOutput("\u{23FA} Writing to main.swift")
        #expect(running == .toolRunning)

        let completed = await detector.analyzeOutput("Task completed \u{2713}")
        #expect(completed == .completed)
    }
}

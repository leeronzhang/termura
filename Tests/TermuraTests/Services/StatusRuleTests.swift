@testable import Termura
import Testing

@Suite("StatusRule")
struct StatusRuleTests {
    // MARK: - Pattern.contains

    @Test("contains matches exact substring")
    func containsExact() {
        let rule = StatusRule(.error, .contains("fatal:"), label: "test")
        #expect(rule.matches("git: fatal: not a repository"))
    }

    @Test("contains does NOT match different case")
    func containsCaseSensitive() {
        let rule = StatusRule(.error, .contains("Fatal:"), label: "test")
        #expect(!rule.matches("fatal: error"))
    }

    // MARK: - Pattern.containsCaseInsensitive

    @Test("containsCaseInsensitive matches regardless of case")
    func caseInsensitive() {
        let rule = StatusRule(.error, .containsCaseInsensitive("api error"), label: "test")
        #expect(rule.matches("API Error: 429"))
        #expect(rule.matches("api error: rate limit"))
        #expect(rule.matches("An API ERROR occurred"))
    }

    // MARK: - Pattern.suffix

    @Test("suffix matches at end only")
    func suffixEnd() {
        let rule = StatusRule(.waitingInput, .suffix("> "), label: "test")
        #expect(rule.matches("claude> "))
        #expect(!rule.matches("> hello"))
        #expect(!rule.matches("no prompt here"))
    }

    // MARK: - Individual rule verification (parameterized)

    @Test("Each waitingInput rule matches its intended text", arguments: [
        ("prompt-suffix", "Some output\n> "),
        ("prompt-suffix-nl", "Some output\n>\n"),
        ("confirm-yn", "Proceed? [Y/n]"),
        ("confirm-yN", "Delete files? [y/N]"),
        ("proceed-prompt", "Do you want to proceed with this?"),
        ("permission-prompt", "Requesting permission to write files") // tightened: "permission to"
    ])
    func waitingInputRules(label: String, text: String) {
        let rule = AgentStateDetector.statusRules.first { $0.label == label }
        #expect(rule != nil, "Rule '\(label)' not found in statusRules")
        #expect(rule?.matches(text) == true, "Rule '\(label)' should match: \(text)")
        #expect(rule?.status == .waitingInput)
    }

    @Test("Each error rule matches its intended text", arguments: [
        ("api-error", "API error: 429 Too Many Requests"),
        ("rate-limit", "Rate limit exceeded, retrying..."),
        ("fatal", "fatal: not a git repository"),
        ("panic", "panic: runtime error"),
        ("traceback", "Traceback (most recent call last):"),
        ("error-colon", "error: cannot find module")
    ])
    func errorRules(label: String, text: String) {
        let rule = AgentStateDetector.statusRules.first { $0.label == label }
        #expect(rule != nil, "Rule '\(label)' not found")
        #expect(rule?.matches(text) == true)
        #expect(rule?.status == .error)
    }

    @Test("Each toolRunning rule matches its intended text", arguments: [
        ("record-icon", "\u{23FA} Writing to main.swift"),
        ("running-label", "Running: npm test"),
        ("executing-label", "Executing: git pull"),
        ("writing-to", "Writing to /tmp/output.txt"),
        ("tool-use-tag", "tool_use: bash"),
        ("bash-call", "bash(echo hello)")
    ])
    func toolRunningRules(label: String, text: String) {
        let rule = AgentStateDetector.statusRules.first { $0.label == label }
        #expect(rule != nil, "Rule '\(label)' not found")
        #expect(rule?.matches(text) == true)
        #expect(rule?.status == .toolRunning)
    }

    @Test("Each thinking rule matches its intended text", arguments: [
        ("thinking-word", "Thinking about the approach..."),
        ("generating-word", "Generating response"),
        ("braille-spinner-1", "Loading \u{280B}"),
        ("braille-spinner-2", "Working \u{2819}"),
        ("braille-spinner-3", "Compiling \u{2839}")
    ])
    func thinkingRules(label: String, text: String) {
        let rule = AgentStateDetector.statusRules.first { $0.label == label }
        #expect(rule != nil, "Rule '\(label)' not found")
        #expect(rule?.matches(text) == true)
        #expect(rule?.status == .thinking)
    }

    @Test("Each completed rule matches its intended text", arguments: [
        ("task-completed", "Task completed successfully"),
        ("done-bang", "Done! All files updated."),
        ("finished-word", "Build finished in 3.2s"),
        ("checkmark", "All tests passed \u{2713}")
    ])
    func completedRules(label: String, text: String) {
        let rule = AgentStateDetector.statusRules.first { $0.label == label }
        #expect(rule != nil, "Rule '\(label)' not found")
        #expect(rule?.matches(text) == true)
        #expect(rule?.status == .completed)
    }

    // MARK: - False positive resistance

    @Test("'error' without colon does not trigger error status")
    func errorWithoutColon() {
        let errorRules = AgentStateDetector.statusRules.filter { $0.status == .error }
        let text = "This is not an error, just a mention of the word error"
        for rule in errorRules {
            #expect(!rule.matches(text), "Rule '\(rule.label)' false-positive on: \(text)")
        }
    }

    @Test("'permission denied' does not trigger waitingInput")
    func permissionDeniedNotWaiting() {
        guard let rule = AgentStateDetector.statusRules.first(
            where: { $0.label == "permission-prompt" }
        ) else {
            Issue.record("Rule 'permission-prompt' not found")
            return
        }
        #expect(!rule.matches("permission denied"))
        #expect(!rule.matches("no permission for this"))
    }

    @Test("'>' in middle of text does not trigger waitingInput")
    func greaterThanInMiddle() {
        let suffixRules = AgentStateDetector.statusRules.filter {
            $0.status == .waitingInput && $0.label.hasPrefix("prompt-suffix")
        }
        for rule in suffixRules {
            #expect(!rule.matches("value > threshold in test"))
        }
    }

    // MARK: - Priority ordering

    @Test("waitingInput has higher priority than error when both match")
    func priorityWaitingOverError() async {
        let detector = AgentStateDetector(sessionID: SessionID())
        _ = await detector.detectFromCommand("claude")
        // Text matches both error ("error:") and waitingInput (suffix "> ")
        let status = await detector.analyzeOutput("error: something\n> ")
        #expect(status == .waitingInput)
    }

    @Test("State machine blocks impossible transitions (idle -> completed)")
    func stateTransitionBlocked() async {
        let detector = AgentStateDetector(sessionID: SessionID())
        _ = await detector.detectFromCommand("claude")
        // idle -> completed should be blocked (must go through thinking first)
        let status = await detector.analyzeOutput("Task completed successfully")
        #expect(status == .idle)
    }

    @Test("Valid transition works when cooldown is satisfied (idle -> thinking)")
    func stateTransitionAllowed() async {
        let detector = AgentStateDetector(sessionID: SessionID())
        _ = await detector.detectFromCommand("claude")
        // idle -> thinking: valid, first transition has no cooldown predecessor
        let status = await detector.analyzeOutput("Thinking about the problem")
        #expect(status == .thinking)
    }

    @Test("All statusRules have unique labels")
    func uniqueLabels() {
        let labels = AgentStateDetector.statusRules.map(\.label)
        let unique = Set(labels)
        #expect(labels.count == unique.count, "Duplicate rule labels found")
    }
}

import Testing
@testable import Termura

@Suite("ShellIntegrationState FSM")
struct ShellIntegrationStateTests {

    // MARK: - Valid transitions

    @Test("idle + promptStarted → promptActive")
    func idleToPromptActive() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        guard case .promptActive = state.phase else {
            Issue.record("Expected .promptActive, got \(state.phase)")
            return
        }
    }

    @Test("promptActive + commandStarted → commandInput")
    func promptToCommandInput() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        guard case .commandInput = state.phase else {
            Issue.record("Expected .commandInput, got \(state.phase)")
            return
        }
    }

    @Test("commandInput + executionStarted → executing")
    func commandInputToExecuting() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        state.apply(.executionStarted)
        guard case .executing = state.phase else {
            Issue.record("Expected .executing, got \(state.phase)")
            return
        }
    }

    @Test("executing + executionFinished → idle")
    func executingToIdle() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        state.apply(.executionStarted)
        state.apply(.executionFinished(exitCode: 0))
        guard case .idle = state.phase else {
            Issue.record("Expected .idle, got \(state.phase)")
            return
        }
    }

    @Test("Full command cycle transitions correctly")
    func fullCycle() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        state.apply(.executionStarted)
        state.apply(.executionFinished(exitCode: 1))
        state.apply(.promptStarted)
        guard case .promptActive = state.phase else {
            Issue.record("Expected .promptActive after restart, got \(state.phase)")
            return
        }
    }

    // MARK: - Invalid transitions (should not crash)

    @Test("Invalid: idle + executionFinished → stays idle")
    func invalidIdleExecutionFinished() {
        var state = ShellIntegrationState()
        // Should not crash
        state.apply(.executionFinished(exitCode: 0))
        guard case .idle = state.phase else {
            Issue.record("Expected .idle after invalid transition, got \(state.phase)")
            return
        }
    }

    @Test("Invalid: commandInput + promptStarted → does not crash")
    func invalidCommandInputPromptStarted() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        // This is an invalid transition — should silently stay
        state.apply(.executionFinished(exitCode: 0))
        // No crash = pass
    }

    @Test("executionStartTime is set when executing")
    func executionStartTimeSet() {
        var state = ShellIntegrationState()
        state.apply(.promptStarted)
        state.apply(.commandStarted)
        #expect(state.executionStartTime == nil)
        state.apply(.executionStarted)
        #expect(state.executionStartTime != nil)
    }
}

// Expose phase for test inspection
extension ShellIntegrationPhase: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: return "idle"
        case .promptActive: return "promptActive"
        case .commandInput(let s): return "commandInput(\(s))"
        case .executing(let cmd, _): return "executing(\(cmd))"
        }
    }
}

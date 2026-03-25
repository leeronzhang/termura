import Foundation
import Testing
@testable import Termura

@Suite("ContextWindowMonitor")
struct ContextWindowMonitorTests {
    private func makeState(
        sessionID: SessionID = SessionID(),
        tokenCount: Int,
        limit: Int = AppConfig.ContextWindow.claudeCodeLimit
    ) -> AgentState {
        AgentState(
            sessionID: sessionID,
            agentType: .claudeCode,
            tokenCount: tokenCount,
            contextWindowLimit: limit
        )
    }

    // MARK: - Alert generation

    @Test("No alert below warning threshold")
    func noAlertBelowWarning() async {
        let monitor = ContextWindowMonitor()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let safeTokens = Int(Double(limit) * 0.7)
        let state = makeState(tokenCount: safeTokens)
        let alert = await monitor.evaluate(state: state)
        #expect(alert == nil)
    }

    @Test("Warning alert at warning threshold")
    func warningAtThreshold() async {
        let monitor = ContextWindowMonitor()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * AppConfig.ContextWindow.warningThreshold) + 1
        let state = makeState(tokenCount: tokens)
        let alert = await monitor.evaluate(state: state)
        #expect(alert != nil)
        #expect(alert?.level == .warning)
    }

    @Test("Critical alert at critical threshold")
    func criticalAtThreshold() async {
        let monitor = ContextWindowMonitor()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * AppConfig.ContextWindow.criticalThreshold) + 1
        let state = makeState(tokenCount: tokens)
        let alert = await monitor.evaluate(state: state)
        #expect(alert != nil)
        #expect(alert?.level == .critical)
    }

    @Test("Alert contains correct fields")
    func alertFields() async {
        let monitor = ContextWindowMonitor()
        let sid = SessionID()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * 0.85)
        let state = makeState(sessionID: sid, tokenCount: tokens)
        let alert = await monitor.evaluate(state: state)
        #expect(alert?.sessionID == sid)
        #expect(alert?.agentType == .claudeCode)
        #expect(alert?.estimatedTokens == tokens)
        #expect(alert?.contextLimit == limit)
    }

    // MARK: - Cooldown

    @Test("Cooldown suppresses second alert")
    func cooldownSuppressesSecond() async {
        let monitor = ContextWindowMonitor()
        let sid = SessionID()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * 0.85)
        let state = makeState(sessionID: sid, tokenCount: tokens)

        let first = await monitor.evaluate(state: state)
        #expect(first != nil)

        let second = await monitor.evaluate(state: state)
        #expect(second == nil)
    }

    @Test("Reset cooldown allows new alert")
    func resetAllowsNewAlert() async {
        let monitor = ContextWindowMonitor()
        let sid = SessionID()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * 0.85)
        let state = makeState(sessionID: sid, tokenCount: tokens)

        _ = await monitor.evaluate(state: state)
        await monitor.reset(for: sid)

        let afterReset = await monitor.evaluate(state: state)
        #expect(afterReset != nil)
    }

    @Test("Cooldown is per-session")
    func cooldownPerSession() async {
        let monitor = ContextWindowMonitor()
        let limit = AppConfig.ContextWindow.claudeCodeLimit
        let tokens = Int(Double(limit) * 0.85)

        let stateA = makeState(sessionID: SessionID(), tokenCount: tokens)
        let stateB = makeState(sessionID: SessionID(), tokenCount: tokens)

        let alertA = await monitor.evaluate(state: stateA)
        let alertB = await monitor.evaluate(state: stateB)
        #expect(alertA != nil)
        #expect(alertB != nil)
    }

    // MARK: - Edge cases

    @Test("Zero context limit returns nil")
    func zeroContextLimit() async {
        let monitor = ContextWindowMonitor()
        let state = makeState(tokenCount: 1000, limit: 0)
        let alert = await monitor.evaluate(state: state)
        #expect(alert == nil)
    }
}

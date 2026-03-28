import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentCoordinator")

/// Coordinates agent detection, state management, risk monitoring, and context
/// window alerts for a terminal session.
///
/// Extracted from `TerminalViewModel` to reduce its init parameter count and
/// isolate agent-related responsibilities behind a single facade.
@MainActor
final class AgentCoordinator: ObservableObject {
    // MARK: - Published state (forwarded to TerminalViewModel via Combine)

    @Published var pendingRiskAlert: RiskAlert?
    @Published var contextWindowAlert: ContextWindowAlert?

    // MARK: - Dependencies

    let agentDetector: AgentStateDetector
    let contextWindowMonitor: ContextWindowMonitor
    weak var agentStateStore: AgentStateStore?
    private let metricsCollector: (any MetricsCollectorProtocol)?

    // MARK: - Agent detection state

    var agentDetectionBuffer = ""
    var hasDetectedAgentFromOutput = false
    var lastDetectedAgentType: AgentType?

    // MARK: - Init

    init(
        sessionID: SessionID,
        agentStateStore: AgentStateStore? = nil,
        metricsCollector: (any MetricsCollectorProtocol)? = nil
    ) {
        agentDetector = AgentStateDetector(sessionID: sessionID)
        contextWindowMonitor = ContextWindowMonitor()
        self.agentStateStore = agentStateStore
        self.metricsCollector = metricsCollector
    }

    // MARK: - Agent detection from commands

    /// Detect agent type from a submitted command and update session/agent state.
    func detectAgentFromCommand(
        _ command: String,
        sessionStore: any SessionStoreProtocol,
        sessionID: SessionID
    ) {
        let detector = agentDetector
        let stateStore = agentStateStore
        Task { @MainActor in
            guard let agentType = await detector.detectFromCommand(command) else { return }
            let agentState = await detector.buildState()
            sessionStore.renameSession(id: sessionID, title: agentType.displayName)
            sessionStore.setAgentType(id: sessionID, type: agentType)
            if let state = agentState {
                stateStore?.update(state: state)
            }
        }
    }

    // MARK: - Agent detection from output

    /// Signature patterns in terminal output that identify a running agent.
    private static let outputSignatures: [(pattern: String, type: AgentType)] = [
        ("claude code", .claudeCode),
        ("anthropic", .claudeCode),
        ("openai codex", .codex),
        (">_ openai codex", .codex),
        ("aider v", .aider),
        ("opencode", .openCode),
        ("gemini cli", .gemini),
        ("gemini code", .gemini)
    ]

    /// Unicode symbols commonly used as status indicators in terminal titles.
    private static let symbolPrefixSet: CharacterSet = {
        CharacterSet(charactersIn:
            "\u{2733}\u{273B}\u{2731}" + // asterisks
            "\u{2726}\u{2605}\u{2606}" + // stars
            "\u{00B7}\u{2022}\u{2027}\u{2219}\u{22C5}\u{2024}\u{2981}" + // dots/bullets (standard)
            "\u{0387}\u{FF65}\u{30FB}\u{16EB}\u{1427}" + // dot look-alikes (Greek, halfwidth, katakana, runic, Canadian)
            "\u{25CF}\u{25CB}\u{25C9}\u{2B24}\u{2B58}\u{26AB}\u{26AA}" + // circles
            "\u{25AA}\u{25AB}\u{25C6}\u{25C7}" + // geometric
            "\u{203A}\u{276F}\u{2192}\u{26A1}" + // arrows/prompt
            "\u{2714}\u{2718}\u{23F3}" + // status
            "\u{2012}\u{2013}\u{2014}\u{2015}" + // dashes
            "\u{FEFF}\u{200B}\u{200C}\u{200D}\u{2060}\u{00AD}" // invisible/format chars
        )
    }()

    /// Returns true for non-ASCII Unicode scalars that belong to symbol or format categories
    /// and are therefore safe to strip as leading title prefixes. ASCII punctuation is excluded
    /// to avoid stripping legitimate characters like "." or "!" that may start a title.
    private static func isStrippableSymbolCategory(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value > 0x007F else { return false }
        switch scalar.properties.generalCategory {
        case .format, .otherSymbol, .mathSymbol, .modifierSymbol:
            return true
        case .otherPunctuation:
            // Strip non-ASCII "other punctuation" (covers dot look-alikes in any script).
            return true
        default:
            return false
        }
    }

    /// Strips known agent icon prefixes from OSC terminal titles.
    static func stripAgentPrefixes(_ title: String) -> String {
        var stripped = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let multiCharPrefixes = [">_"]
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in multiCharPrefixes where stripped.hasPrefix(prefix) {
                stripped = String(stripped.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
            if let first = stripped.unicodeScalars.first,
               symbolPrefixSet.contains(first) || isStrippableSymbolCategory(first) {
                stripped = String(stripped.unicodeScalars.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }
        return stripped.isEmpty ? title : stripped
    }

    /// Scan terminal output for agent signatures and update session when detected.
    func detectAgentFromOutput(
        _ text: String,
        sessionStore: any SessionStoreProtocol,
        sessionID: SessionID
    ) async {
        agentDetectionBuffer += text
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        if agentDetectionBuffer.count > maxLen {
            agentDetectionBuffer = String(agentDetectionBuffer.suffix(maxLen))
        }
        let lower = agentDetectionBuffer.lowercased()
        for (pattern, type) in Self.outputSignatures where lower.contains(pattern) {
            if hasDetectedAgentFromOutput, lastDetectedAgentType == type { return }
            hasDetectedAgentFromOutput = true
            lastDetectedAgentType = type
            if let collector = metricsCollector {
                Task { await collector.increment(.agentDetected) }
            }
            sessionStore.renameSession(id: sessionID, title: type.displayName)
            sessionStore.setAgentType(id: sessionID, type: type)
            await agentDetector.setDetectedType(type)
            if let state = await agentDetector.buildState() {
                agentStateStore?.update(state: state)
            }
            return
        }
    }

    // MARK: - Output analysis (background)

    /// Analyze output text for agent status changes, token stats, and risk patterns.
    /// Runs off the main actor: only accesses `let` actor dependencies and explicitly
    /// hops to `@MainActor` via `MainActor.run` for the `@Published` risk alert update.
    nonisolated func analyzeOutput(
        _ stripped: String,
        sessionID: SessionID,
        tokenCountingService: any TokenCountingServiceProtocol
    ) async {
        let detector = agentDetector

        _ = await detector.analyzeOutput(stripped)
        if let stats = await detector.parseTokenStats(stripped) {
            if let cached = stats.cachedTokens, cached > 0 {
                await tokenCountingService.accumulateCached(for: sessionID, count: cached)
            }
            if let cost = stats.totalCost {
                await detector.updateCost(cost)
            }
        }
        if let risk = InterventionService.detectRisk(in: stripped) {
            await MainActor.run { @Sendable [weak self] in
                self?.pendingRiskAlert = risk
            }
        }
    }

    // MARK: - Agent state update

    /// Build agent state from detector + token service, update store, evaluate context alerts.
    func updateAgentState(
        tokenCountingService: any TokenCountingServiceProtocol,
        sessionID: SessionID
    ) async {
        let detector = agentDetector
        let breakdown = await tokenCountingService.tokenBreakdown(for: sessionID)
        guard var state = await detector.buildState(tokenCount: breakdown.totalTokens) else { return }
        state.inputTokens = breakdown.inputTokens
        state.outputTokens = breakdown.outputTokens
        state.cachedTokens = breakdown.cachedTokens
        agentStateStore?.update(state: state)

        let hasParsedData = state.cachedTokens > 0 || state.estimatedCostUSD > 0
        if hasParsedData {
            let monitor = contextWindowMonitor
            if let alert = await monitor.evaluate(state: state) {
                contextWindowAlert = alert
            }
        }
    }
}

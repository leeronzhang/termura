import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateDetector")

/// Detects AI agent type and operational status from PTY output.
/// Uses startup command matching and ongoing output pattern analysis.
actor AgentStateDetector {
    var detectedType: AgentType?
    var currentStatus: AgentStatus = .idle
    private var detectedAt: Date?
    private var lastStatusChange: Date?
    private var parsedCost: Double = 0
    private let sessionID: SessionID
    private let clock: any AppClock
    /// Last file path detected from "Writing to <path>" output; cleared on non-toolRunning transitions.
    private var activeFilePath: String?
    /// Brief description of what the agent is currently doing; populated from output patterns.
    private var currentTask: String?

    init(sessionID: SessionID, clock: any AppClock = LiveClock()) {
        self.sessionID = sessionID
        self.clock = clock
    }

    // MARK: - Command Detection

    /// Analyze a command string to detect agent launch.
    func detectFromCommand(_ command: String) -> AgentType? {
        let cmd = command.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sid = sessionID
        for (pattern, type) in Self.launchPatterns {
            if cmd.hasPrefix(pattern) || cmd.contains("/\(pattern)") {
                detectedType = type
                currentStatus = .idle
                detectedAt = clock.now()
                logger.info("Detected agent \(type.rawValue) in session \(sid)")
                return type
            }
        }
        return nil
    }

    /// Update the accumulated cost from parsed agent output.
    func updateCost(_ cost: Double) {
        parsedCost = cost
    }

    /// Set or update the detected agent type (used when detection happens outside the detector).
    func setDetectedType(_ type: AgentType) {
        let sid = sessionID
        detectedType = type
        currentStatus = .idle
        detectedAt = clock.now()
        parsedCost = 0
        logger.info("Agent \(type.rawValue) set externally in session \(sid)")
    }

    // MARK: - Output Analysis

    /// Apply a structured signal (e.g. from OSC 9/99/777) directly to agent status,
    /// bypassing text-rule analysis. Writes lastStatusChange to protect the new state
    /// from being immediately overridden by the text heuristic cooldown.
    ///
    /// Validates against validTransitions — structured signals must not produce impossible
    /// state jumps. Invalid transitions are logged and ignored rather than crashing.
    ///
    /// Phase 2 hook: wired by AgentCoordinator.applyStructuredAgentSignal when an
    /// authoritative OSC status frame is received.
    func applyStructuredSignal(_ status: AgentStatus) {
        guard Self.validTransitions[currentStatus]?.contains(status) == true else {
            let sid = sessionID
            logger.warning(
                "OSC signal '\(status.rawValue)' ignored: invalid transition from '\(currentStatus.rawValue)' in session \(sid)"
            )
            return
        }
        currentStatus = status
        lastStatusChange = clock.now()
    }

    /// Analyze a batch of terminal output; returns current status after processing.
    @discardableResult func analyzeOutput(_ text: String) -> AgentStatus {
        guard detectedType != nil else { return currentStatus }
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        // Keep as Substring — avoids a String copy when text exceeds the analysis window.
        // Materialized to String only on the rare transition path where regex calls need it.
        let sample: Substring = text.count > maxLen ? text.suffix(maxLen) : text[text.startIndex...]
        // lowercased() allocates a new String; skip it entirely in states whose reachable
        // rule set contains no .containsCaseInsensitive rules (e.g. .completed, .error).
        let lowercasedSample: String = Self.statesNeedingLowercased.contains(currentStatus)
            ? sample.lowercased()
            : ""

        // Extract task description on every output batch in active states — not just on
        // transitions. Claude Code stays in toolRunning across many tool invocations without
        // a state change, so tying extraction to transitions means currentTask gets stuck.
        // extractCurrentTask has its own fast-path literal guard (O(1) when no anchor keyword).
        let sampleString = String(sample)
        if currentStatus == .toolRunning || currentStatus == .thinking {
            if let task = extractCurrentTask(from: sampleString) {
                currentTask = task
            }
        }

        guard let matched = evaluateRules(sample, lowercased: lowercasedSample),
              matched != currentStatus else { return currentStatus }

        // Enforce valid state transitions.
        guard Self.validTransitions[currentStatus]?.contains(matched) ?? false else { return currentStatus }

        // Enforce cooldown between transitions to avoid flip-flopping on noisy output.
        let now = clock.now()
        if let last = lastStatusChange,
           now.timeIntervalSince(last) < AppConfig.Agent.statusChangeCooldown { return currentStatus }

        currentStatus = matched
        lastStatusChange = now
        // Extract active file path when a tool-write is in progress; clear it otherwise.
        // Guard with a cheap contains() before running the regex to avoid unnecessary
        // regex execution when toolRunning was triggered by a different rule (e.g. "Running:").
        if matched == .toolRunning && sample.contains("Writing to") {
            activeFilePath = extractActiveFilePath(from: sampleString) ?? activeFilePath
        } else if matched == .idle || matched == .completed || matched == .error {
            activeFilePath = nil
        }
        // Clear task on terminal states; active-state extraction handled above.
        if matched == .idle || matched == .completed {
            currentTask = nil
        }
        return currentStatus
    }

    /// Build a full AgentState snapshot.
    func buildState(tokenCount: Int = 0) -> AgentState? {
        guard let type = detectedType else { return nil }
        return AgentState(
            sessionID: sessionID,
            agentType: type,
            status: currentStatus,
            currentTask: currentTask,
            tokenCount: tokenCount,
            estimatedCostUSD: parsedCost,
            activeFilePath: activeFilePath,
            startedAt: detectedAt ?? clock.now()
        )
    }

    /// Reset detection state.
    func reset() {
        detectedType = nil
        currentStatus = .idle
        detectedAt = nil
        lastStatusChange = nil
        activeFilePath = nil
        currentTask = nil
    }
}

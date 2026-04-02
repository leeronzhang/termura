import Foundation
import Observation

/// Per-session sidebar presentation state for agent metadata.
/// Isolates row-level updates so the entire session list does not re-render
/// when agent status or elapsed duration changes elsewhere.
@Observable
@MainActor
final class AgentSidebarRowState {
    let sessionID: SessionID

    private(set) var status: AgentStatus?
    private(set) var agentType: AgentType?
    private(set) var tokenSummary: String?
    private(set) var durationText: String?
    private(set) var currentTaskSnippet: String?

    @ObservationIgnored private var startedAt: Date?

    init(sessionID: SessionID) {
        self.sessionID = sessionID
    }

    func apply(_ state: AgentState, now: Date) {
        startedAt = state.startedAt
        status = state.status
        agentType = state.agentType
        tokenSummary = state.tokenCount > 0 ? MetadataFormatter.formatTokenCount(state.tokenCount) : nil
        currentTaskSnippet = state.currentTask
        refreshDuration(now: now)
    }

    func clear() {
        startedAt = nil
        status = nil
        agentType = nil
        tokenSummary = nil
        durationText = nil
        currentTaskSnippet = nil
    }

    func refreshDuration(now: Date) {
        guard let startedAt else {
            durationText = nil
            return
        }
        let elapsed = now.timeIntervalSince(startedAt)
        durationText = elapsed > 0 ? MetadataFormatter.formatDuration(elapsed) : nil
    }
}

import SwiftUI

/// Multi-agent overview panel showing all detected agents and their statuses.
/// Accessible via Cmd+Shift+A or the Agents sidebar tab.
struct AgentDashboardView: View {
    @ObservedObject var agentStore: AgentStateStore
    let sessionTitles: [SessionID: String]
    let onJumpToSession: (SessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                if agentStore.agents.isEmpty {
                    emptyState
                } else {
                    agentList
                }
            }
            if !agentStore.agents.isEmpty {
                Divider()
                summaryFooter
            }
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Agents")
                .panelHeaderStyle()
            Spacer()
            Text("\(agentStore.activeAgentCount) active")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    // MARK: - List

    private var agentList: some View {
        LazyVStack(spacing: AppUI.Spacing.xs) {
            ForEach(sortedAgents) { agent in
                agentRow(agent)
            }
        }
        .padding(.vertical, AppUI.Spacing.smMd)
        .padding(.horizontal, AppUI.Spacing.sm)
    }

    private var sortedAgents: [AgentState] {
        agentStore.agents.values.sorted { lhs, rhs in
            let lhsPri = Self.sortPriority(lhs)
            let rhsPri = Self.sortPriority(rhs)
            if lhsPri != rhsPri { return lhsPri < rhsPri }
            return lhs.startedAt > rhs.startedAt
        }
    }

    private static func sortPriority(_ agent: AgentState) -> Int {
        switch agent.status {
        case .waitingInput: 0
        case .error: 1
        case .thinking: 2
        case .toolRunning: 3
        case .idle: 4
        case .completed: 5
        }
    }

    private func agentRow(_ agent: AgentState) -> some View {
        Button {
            onJumpToSession(agent.sessionID)
        } label: {
            HStack(alignment: .top, spacing: AppUI.Spacing.md) {
                AgentStatusBadgeView(status: agent.status, agentType: agent.agentType)
                    .padding(.top, AppUI.Spacing.xs)
                VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                    agentTitleRow(agent)
                    if let task = agent.currentTask {
                        Text(task)
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if agent.tokenCount > 0 {
                        TokenProgressView(
                            estimatedTokens: agent.tokenCount,
                            contextLimit: agent.contextWindowLimit
                        )
                        .frame(maxWidth: AppConfig.UI.agentDashboardLabelWidth)
                    }
                }
                Spacer(minLength: 0)
                elapsedLabel(agent)
            }
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.md)
            .background(
                agent.needsAttention
                    ? Color.yellow.opacity(AppUI.Opacity.highlight)
                    : Color.clear
            )
            .cornerRadius(AppUI.Radius.md)
        }
        .buttonStyle(.plain)
    }

    private func agentTitleRow(_ agent: AgentState) -> some View {
        HStack(spacing: AppUI.Spacing.xs) {
            Text(agent.agentType.displayName)
                .font(AppUI.Font.bodyMedium)
            if let title = sessionTitles[agent.sessionID] {
                Text("- \(title)")
                    .font(AppUI.Font.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func elapsedLabel(_ agent: AgentState) -> some View {
        let elapsed = Date().timeIntervalSince(agent.startedAt)
        return Text(MetadataFormatter.formatDuration(elapsed))
            .font(AppUI.Font.captionMono)
            .foregroundColor(.secondary)
    }

    // MARK: - Summary Footer

    private var summaryFooter: some View {
        HStack {
            Text("Total")
                .sectionLabelStyle()
            Spacer()
            Text(MetadataFormatter.formatTokenCount(agentStore.totalEstimatedTokens))
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: "cpu")
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text("No agents detected")
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppUI.Spacing.xxxxl)
    }
}

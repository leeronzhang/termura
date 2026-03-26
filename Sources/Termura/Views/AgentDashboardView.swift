import SwiftUI

/// Multi-agent overview panel showing all detected agents and their statuses.
/// Accessible via toolbar or notification jump.
struct AgentDashboardView: View {
    @ObservedObject var agentStore: AgentStateStore
    let onJumpToSession: (SessionID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                if agentStore.agents.isEmpty {
                    emptyState
                } else {
                    agentList
                }
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
        agentStore.agents.values
            .sorted { $0.needsAttention && !$1.needsAttention }
    }

    private func agentRow(_ agent: AgentState) -> some View {
        Button {
            onJumpToSession(agent.sessionID)
        } label: {
            HStack(spacing: AppUI.Spacing.md) {
                AgentStatusBadgeView(status: agent.status, agentType: agent.agentType)
                VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                    Text(agent.agentType.rawValue)
                        .font(AppUI.Font.bodyMedium)
                    if let task = agent.currentTask {
                        Text(task)
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if agent.tokenCount > 0 {
                    TokenProgressView(
                        estimatedTokens: agent.tokenCount,
                        contextLimit: agent.contextWindowLimit
                    )
                    .frame(width: AppConfig.UI.agentDashboardLabelWidth)
                }
            }
            .padding(.horizontal, AppUI.Spacing.md)
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

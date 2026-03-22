import SwiftUI

/// Multi-agent overview panel showing all detected agents and their statuses.
/// Accessible via toolbar or notification jump.
struct AgentDashboardView: View {
    @ObservedObject var agentStore: AgentStateStore
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
        }
        .frame(width: AppConfig.Timeline.panelWidth)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Agents")
                .panelHeaderStyle()
            Spacer()
            Text("\(agentStore.activeAgentCount) active")
                .font(DS.Font.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - List

    private var agentList: some View {
        LazyVStack(spacing: DS.Spacing.xs) {
            ForEach(sortedAgents) { agent in
                agentRow(agent)
            }
        }
        .padding(.vertical, DS.Spacing.md)
    }

    private var sortedAgents: [AgentState] {
        agentStore.agents.values
            .sorted { $0.needsAttention && !$1.needsAttention }
    }

    private func agentRow(_ agent: AgentState) -> some View {
        Button {
            onJumpToSession(agent.sessionID)
        } label: {
            HStack(spacing: DS.Spacing.md) {
                AgentStatusBadgeView(status: agent.status, agentType: agent.agentType)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(agent.agentType.rawValue)
                        .font(DS.Font.bodyMedium)
                    if let task = agent.currentTask {
                        Text(task)
                            .font(DS.Font.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if agent.tokenCount > 0 {
                    Text(formattedTokens(agent.tokenCount))
                        .font(DS.Font.captionMono)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.md)
            .background(
                agent.needsAttention
                    ? Color.yellow.opacity(DS.Opacity.highlight)
                    : Color.clear
            )
            .cornerRadius(DS.Radius.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(systemName: "cpu")
                .font(DS.Font.title1)
                .foregroundColor(.secondary.opacity(DS.Opacity.dimmed))
            Text("No agents detected")
                .font(DS.Font.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.xxxl)
    }

    // MARK: - Helpers

    private func formattedTokens(_ count: Int) -> String {
        count >= 1000 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)"
    }
}

import SwiftUI

/// Narrow right-side panel displaying session metadata: agent info, directory,
/// token breakdown, cost, command count, and duration.
struct SessionMetadataBarView: View {
    let metadata: SessionMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppUI.Spacing.lgXl) {
                    if metadata.currentAgentType != nil {
                        agentSection
                    }
                    directorySection
                    tokenSection
                    if metadata.estimatedCostUSD > 0 {
                        costSection
                    }
                    commandSection
                    durationSection
                }
                .padding(.horizontal, AppUI.Spacing.xxxl)
                .padding(.vertical, AppUI.Spacing.lgXl)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var panelHeader: some View {
        Text("Session")
            .panelHeaderStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.vertical, AppUI.Spacing.mdLg)
    }

    // MARK: - Agent

    @ViewBuilder
    private var agentSection: some View {
        if let agentType = metadata.currentAgentType,
           let agentStatus = metadata.currentAgentStatus {
            metadataItem(label: "Agent") {
                HStack(spacing: AppUI.Spacing.smMd) {
                    AgentStatusBadgeView(status: agentStatus, agentType: agentType)
                    Text(agentType.displayName)
                        .font(AppUI.Font.bodyMedium)
                }
                Text(MetadataFormatter.formatAgentStatus(agentStatus))
                    .font(AppUI.Font.caption)
                    .foregroundColor(agentStatusColor(agentStatus))
                if let task = metadata.currentAgentTask {
                    Text(task)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if metadata.agentElapsedTime > 0 {
                    breakdownRow(
                        "Elapsed",
                        MetadataFormatter.formatDuration(metadata.agentElapsedTime)
                    )
                }
                if metadata.activeAgentCount > 1 {
                    Text("\(metadata.activeAgentCount) agents active")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Directory

    private var directorySection: some View {
        metadataItem(label: "Directory") {
            Text(abbreviatedDirectory)
                .font(AppUI.Font.labelMono)
                .foregroundColor(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
                .help(metadata.workingDirectory)
        }
    }

    // MARK: - Tokens

    private var tokenSection: some View {
        metadataItem(label: "Tokens") {
            if metadata.contextWindowLimit > 0 {
                TokenProgressView(
                    estimatedTokens: metadata.estimatedTokenCount,
                    contextLimit: metadata.contextWindowLimit
                )
            }
            if metadata.hasTokenBreakdown {
                tokenBreakdownRows
            } else if metadata.contextWindowLimit <= 0 {
                Text(formattedTokenCount)
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var tokenBreakdownRows: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
            if metadata.inputTokenCount > 0 {
                breakdownRow(
                    "Input",
                    MetadataFormatter.formatTokenCount(metadata.inputTokenCount)
                )
            }
            if metadata.outputTokenCount > 0 {
                breakdownRow(
                    "Output",
                    MetadataFormatter.formatTokenCount(metadata.outputTokenCount)
                )
            }
            if metadata.cachedTokenCount > 0 {
                breakdownRow(
                    "Cached",
                    MetadataFormatter.formatTokenCount(metadata.cachedTokenCount)
                )
            }
        }
    }

    // MARK: - Cost

    private var costSection: some View {
        metadataItem(label: "Cost") {
            Text(MetadataFormatter.formatCost(metadata.estimatedCostUSD))
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Commands

    private var commandSection: some View {
        metadataItem(label: "Commands") {
            Text("\(metadata.commandCount)")
                .font(AppUI.Font.title3Medium)
                .monospacedDigit()
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        metadataItem(label: "Duration") {
            Text(formattedDuration)
                .font(AppUI.Font.title3Medium)
                .monospacedDigit()
        }
    }

    // MARK: - Reusable layouts

    @ViewBuilder
    private func metadataItem(
        label: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text(label)
                .sectionLabelStyle()
            content()
        }
    }

    private func breakdownRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Computed

    private var formattedTokenCount: String {
        MetadataFormatter.formatTokenCount(metadata.estimatedTokenCount)
    }

    private var abbreviatedDirectory: String {
        MetadataFormatter.abbreviateDirectory(metadata.workingDirectory)
    }

    private var formattedDuration: String {
        MetadataFormatter.formatDuration(metadata.sessionDuration)
    }

    private func agentStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .thinking: .blue
        case .toolRunning: .orange
        case .waitingInput: .yellow
        case .error: .red
        case .completed: .green
        }
    }
}

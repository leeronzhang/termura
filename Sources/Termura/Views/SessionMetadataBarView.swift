import SwiftUI

/// Right-side panel combining session metadata (top) and optional command timeline (bottom).
struct SessionMetadataBarView: View {
    let metadata: SessionMetadata
    var timeline: SessionTimeline?
    var onSelectChunkID: ((UUID) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxxxl) {
                    metadataArea
                    if let timeline, !timeline.turns.isEmpty {
                        timelineSection(timeline)
                    }
                }
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

    // MARK: - Metadata

    private var metadataArea: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.lgXl) {
            if metadata.currentAgentType != nil {
                agentSection
            }
            tokenSection
            if metadata.estimatedCostUSD > 0 {
                costSection
            }
            statsSection
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.top, AppUI.Spacing.lgXl)
    }

    // MARK: - Agent

    @ViewBuilder
    private var agentSection: some View {
        if let agentType = metadata.currentAgentType,
           let agentStatus = metadata.currentAgentStatus {
            VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
                HStack(spacing: AppUI.Spacing.smMd) {
                    AgentStatusBadgeView(status: agentStatus, agentType: agentType)
                    Text(agentType.displayName)
                        .font(AppUI.Font.title3Medium)
                }
                HStack {
                    Text(MetadataFormatter.formatAgentStatus(agentStatus))
                        .font(AppUI.Font.labelMono)
                        .foregroundColor(agentStatusColor(agentStatus))
                    Spacer()
                    Text(MetadataFormatter.formatDuration(metadata.sessionDuration))
                        .font(AppUI.Font.labelMono)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                if let task = metadata.currentAgentTask {
                    Text(task)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                if metadata.activeAgentCount > 1 {
                    Text("\(metadata.activeAgentCount) agents active")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Tokens

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
            Text("Tokens")
                .font(AppUI.Font.labelMedium)
                .foregroundColor(.primary)
            if metadata.hasParsedTokenData, metadata.contextWindowLimit > 0 {
                TokenProgressView(
                    estimatedTokens: metadata.estimatedTokenCount,
                    contextLimit: metadata.contextWindowLimit
                )
            }
            tokenBreakdownRows
        }
    }

    private var tokenBreakdownRows: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
            kvRow("Input", MetadataFormatter.formatTokenCount(metadata.inputTokenCount))
            kvRow("Output", MetadataFormatter.formatTokenCount(metadata.outputTokenCount))
            kvRow("Cached", MetadataFormatter.formatTokenCount(metadata.cachedTokenCount))
        }
    }

    // MARK: - Cost

    private var costSection: some View {
        kvRow("Cost", MetadataFormatter.formatCost(metadata.estimatedCostUSD))
    }

    // MARK: - Stats

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
            kvRow("Commands", "\(metadata.commandCount)")
            if metadata.currentAgentType == nil {
                kvRow("Duration", formattedDuration)
            }
        }
    }

    // MARK: - Timeline

    private func timelineSection(_ tl: SessionTimeline) -> some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
            Text("Timeline")
                .font(AppUI.Font.labelMedium)
                .foregroundColor(.primary)
                .padding(.horizontal, AppUI.Spacing.xxxl)
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(tl.turns) { turn in
                    timelineRow(turn)
                }
            }
            .padding(.horizontal, AppUI.Spacing.xxxl)
        }
    }

    private func timelineRow(_ turn: TimelineTurn) -> some View {
        Button {
            onSelectChunkID?(turn.chunkID)
        } label: {
            HStack(spacing: AppUI.Spacing.smMd) {
                Circle()
                    .fill(exitCodeColor(turn.exitCode))
                    .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                Text(turnLabel(turn))
                    .font(AppUI.Font.captionMono)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer()
                Text(formattedTime(turn.startedAt))
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, AppUI.Spacing.smMd)
        }
        .buttonStyle(.plain)
    }

    private func turnLabel(_ turn: TimelineTurn) -> String {
        if !turn.command.isEmpty { return turn.command }
        return "Turn \(turnIndex(turn) + 1)"
    }

    private func turnIndex(_ turn: TimelineTurn) -> Int {
        timeline?.turns.firstIndex(where: { $0.id == turn.id }) ?? 0
    }

    // MARK: - Reusable

    private func kvRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(AppUI.Font.captionMono)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(AppUI.Font.labelMono)
                .foregroundColor(.primary)
                .monospacedDigit()
        }
    }

    // MARK: - Computed

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

    private func exitCodeColor(_ code: Int?) -> Color {
        guard let code else { return .secondary }
        return code == 0 ? .green : .red
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

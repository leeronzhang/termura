import SwiftUI

/// Right-side panel combining session metadata (top) and optional command timeline (bottom).
struct SessionMetadataBarView: View {
    let metadata: SessionMetadata
    var timeline: SessionTimeline?
    var onSelectChunkID: ((UUID) -> Void)?

    @State private var showAllTurns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppUI.Spacing.xxl) {
                    agentCard
                    contextWindowSection
                    currentTaskSection
                    tokenSummarySection
                    activitySection
                }
                .padding(.horizontal, AppUI.Spacing.xxxl)
                .padding(.top, AppUI.Spacing.lgXl)
                .padding(.bottom, AppUI.Spacing.xxxl)
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

    // MARK: - Agent Card

    @ViewBuilder
    private var agentCard: some View {
        if let agentType = metadata.currentAgentType,
           let agentStatus = metadata.currentAgentStatus {
            VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
                // Row 1: badge + name + status
                HStack(spacing: AppUI.Spacing.smMd) {
                    AgentStatusBadgeView(status: agentStatus, agentType: agentType)
                    Text(agentType.displayName)
                        .font(AppUI.Font.title3Medium)
                    Spacer()
                    Text(MetadataFormatter.formatAgentStatus(agentStatus))
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(agentStatusColor(agentStatus))
                }
                // Row 2: duration + cost + rate (compact chips)
                HStack(spacing: AppUI.Spacing.md) {
                    metaChip(
                        icon: "clock",
                        text: MetadataFormatter.formatDuration(metadata.agentElapsedTime)
                    )
                    if metadata.estimatedCostUSD > 0 {
                        metaChip(
                            icon: "dollarsign.circle",
                            text: MetadataFormatter.formatCost(metadata.estimatedCostUSD)
                        )
                    }
                    if tokenRate > 0 {
                        metaChip(
                            icon: "gauge.with.dots.needle.33percent",
                            text: "\(MetadataFormatter.formatTokenCount(tokenRate))/m"
                        )
                    }
                    Spacer()
                }
            }
        } else {
            // Non-agent session
            HStack(spacing: AppUI.Spacing.md) {
                metaChip(
                    icon: "clock",
                    text: MetadataFormatter.formatDuration(metadata.sessionDuration)
                )
                metaChip(
                    icon: "terminal",
                    text: "\(metadata.commandCount) cmds"
                )
                Spacer()
            }
        }
    }

    // MARK: - Context Window

    @ViewBuilder
    private var contextWindowSection: some View {
        if metadata.contextWindowLimit > 0 {
            VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
                sectionLabel("Context Window")

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(AppUI.Opacity.whisper))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(contextBarColor)
                            .frame(
                                width: geo.size.width * min(metadata.contextUsageFraction, 1.0),
                                height: 6
                            )
                    }
                }
                .frame(height: 6)

                // Labels
                HStack {
                    Text("\(Int(metadata.contextUsageFraction * 100))%")
                        .font(AppUI.Font.labelMedium)
                        .foregroundColor(contextBarColor)
                    Spacer()
                    Text(
                        "\(MetadataFormatter.formatTokenCount(metadata.estimatedTokenCount))"
                            + " / \(MetadataFormatter.formatTokenCount(metadata.contextWindowLimit))"
                    )
                    .font(AppUI.Font.captionMono)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Current Task

    @ViewBuilder
    private var currentTaskSection: some View {
        if let task = metadata.currentAgentTask, !task.isEmpty {
            VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
                sectionLabel("Current Task")
                Text(task)
                    .font(AppUI.Font.body)
                    .foregroundColor(.primary.opacity(AppUI.Opacity.strong))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Tokens (compact)

    private var tokenSummarySection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
            sectionLabel("Tokens")
            HStack(spacing: AppUI.Spacing.lg) {
                tokenPill("Out", metadata.outputTokenCount, .blue)
                tokenPill("In", metadata.inputTokenCount, .green)
                tokenPill("Cache", metadata.cachedTokenCount, .purple)
            }
        }
    }

    // MARK: - Activity (Timeline)

    @ViewBuilder
    private var activitySection: some View {
        if let tl = timeline, !tl.turns.isEmpty {
            VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
                HStack {
                    sectionLabel("Activity")
                    Spacer()
                    Text("\(tl.turns.count)")
                        .font(AppUI.Font.captionMono)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, AppUI.Spacing.smMd)
                        .padding(.vertical, AppUI.Spacing.xxs)
                        .background(Color.secondary.opacity(AppUI.Opacity.whisper))
                        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.sm))
                }
                let visible = showAllTurns ? Array(tl.turns) : Array(tl.turns.suffix(3))
                ForEach(visible) { turn in
                    Button { onSelectChunkID?(turn.chunkID) } label: {
                        HStack(spacing: AppUI.Spacing.smMd) {
                            Circle().fill(exitCodeColor(turn.exitCode))
                                .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                            Text(turnLabel(turn)).font(AppUI.Font.captionMono)
                                .lineLimit(1).foregroundColor(.primary)
                            Spacer()
                            Text(formattedTime(turn.startedAt)).font(AppUI.Font.micro)
                                .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
                        }.padding(.vertical, AppUI.Spacing.xs)
                    }.buttonStyle(.plain)
                }
                if tl.turns.count > 3, !showAllTurns {
                    Button {
                        withAnimation(.easeInOut(duration: AppUI.Animation.quick)) { showAllTurns = true }
                    } label: {
                        Text("Show all").font(AppUI.Font.caption).foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, AppUI.Spacing.smMd)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Reusable Components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppUI.Font.micro)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: AppUI.Spacing.xxs) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(AppUI.Font.captionMono)
        }
        .foregroundColor(.secondary)
        .monospacedDigit()
    }

    private func tokenPill(_ label: String, _ value: Int, _ color: Color) -> some View {
        let hasValue = value > 0
        return HStack(spacing: AppUI.Spacing.xxs) {
            RoundedRectangle(cornerRadius: 1)
                .fill(hasValue ? color : color.opacity(AppUI.Opacity.tertiary))
                .frame(width: 3, height: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(MetadataFormatter.formatTokenCount(value))
                    .font(AppUI.Font.labelMono)
                    .foregroundColor(hasValue ? .primary : .secondary)
                    .monospacedDigit()
                Text(label)
                    .font(AppUI.Font.micro)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Computed

    private var tokenRate: Int {
        guard metadata.agentElapsedTime > 60 else { return 0 }
        let total = metadata.inputTokenCount + metadata.outputTokenCount
        return Int(Double(total) / (metadata.agentElapsedTime / 60))
    }

    private var contextBarColor: Color {
        if metadata.contextUsageFraction >= AppConfig.UI.tokenProgressWarningFraction {
            return .red
        } else if metadata.contextUsageFraction >= 0.5 {
            return .orange
        }
        return .accentColor
    }
}

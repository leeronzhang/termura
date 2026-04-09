import SwiftUI

/// Right-side panel combining session metadata (top) and optional command timeline (bottom).
struct SessionMetadataBarView: View {
    let metadata: SessionMetadata
    var sessionTitle: String = "Session"
    var timeline: SessionTimeline?
    var onSelectChunkID: ((UUID) -> Void)?

    @Environment(\.themeManager) var themeManager
    @AppStorage(AppConfig.CostEstimation.subscriptionModeKey) var subscriptionMode: Bool = false
    @State var showAllTurns = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
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
        Text("Inspector")
            .panelHeaderStyle()
            .frame(height: AppConfig.UI.projectPathBarHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppUI.Spacing.xxxl)
            .padding(.top, AppUI.Spacing.md)
            .padding(.bottom, AppUI.Spacing.smMd)
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
        // Only show when real API data is available. Before the first turn completes,
        // tokenCount is heuristic PTY output accumulation — not the API context window.
        let barColor = themeManager.current.foreground
        if metadata.contextWindowLimit > 0, metadata.hasParsedTokenData {
            VStack(alignment: .leading, spacing: AppUI.Spacing.md) {
                sectionLabel("Context Window")

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(AppUI.Opacity.whisper))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor.opacity(AppUI.Opacity.secondary))
                            .frame(
                                width: geo.size.width * min(metadata.contextUsageFraction, 1.0)
                            )
                    }
                }
                .frame(height: 16)

                HStack {
                    Text("\(Int(metadata.contextUsageFraction * 100))%")
                        .font(AppUI.Font.labelMedium)
                        .foregroundColor(.primary)
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

    // MARK: - Reusable Components

    func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppUI.Font.micro)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(0.8)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: AppUI.Spacing.xxs) {
            Image(systemName: icon)
                .font(AppUI.Font.micro)
            Text(text)
                .font(AppUI.Font.captionMono)
        }
        .foregroundColor(.secondary)
        .monospacedDigit()
    }
}

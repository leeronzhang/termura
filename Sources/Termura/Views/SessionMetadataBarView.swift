import SwiftUI

/// Narrow right-side panel displaying session metadata: directory, token usage,
/// command count, and duration. Toggled via toolbar button in TerminalAreaView.
struct SessionMetadataBarView: View {

    let metadata: SessionMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    if metadata.currentAgentType != nil {
                        agentSection
                    }
                    directorySection
                    tokenSection
                    commandSection
                    durationSection
                }
                .padding(DS.Spacing.lg)
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
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
    }

    // MARK: - Agent

    @ViewBuilder
    private var agentSection: some View {
        if let agentType = metadata.currentAgentType,
           let agentStatus = metadata.currentAgentStatus {
            metadataItem(label: "Agent") {
                HStack(spacing: DS.Spacing.md) {
                    AgentStatusBadgeView(status: agentStatus, agentType: agentType)
                    Text(agentType.rawValue)
                        .font(DS.Font.bodyMedium)
                }
                if metadata.activeAgentCount > 1 {
                    Text("\(metadata.activeAgentCount) agents active")
                        .font(DS.Font.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Directory

    private var directorySection: some View {
        metadataItem(label: "Directory") {
            Text(abbreviatedDirectory)
                .font(DS.Font.labelMono)
                .foregroundColor(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
                .help(metadata.workingDirectory)
        }
    }

    // MARK: - Tokens

    private var tokenSection: some View {
        metadataItem(label: "Tokens") {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                ProgressView(value: tokenFraction, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(tokenFraction >= AppConfig.UI.tokenProgressWarningFraction ? .orange : .accentColor)
                Text(formattedTokenCount)
                    .font(DS.Font.label)
                    .foregroundColor(
                        tokenFraction >= AppConfig.UI.tokenProgressWarningFraction ? .orange : .secondary
                    )
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Commands

    private var commandSection: some View {
        metadataItem(label: "Commands") {
            Text("\(metadata.commandCount)")
                .font(DS.Font.title3Medium)
                .monospacedDigit()
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        metadataItem(label: "Duration") {
            Text(formattedDuration)
                .font(DS.Font.title3Medium)
                .monospacedDigit()
        }
    }

    // MARK: - Reusable item layout

    @ViewBuilder
    private func metadataItem<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(label)
                .sectionLabelStyle()
            content()
        }
    }

    // MARK: - Computed

    private var tokenFraction: Double {
        guard AppConfig.AI.contextWarningThreshold > 0 else { return 0 }
        let fraction = Double(metadata.estimatedTokenCount) / Double(AppConfig.AI.contextWarningThreshold)
        return min(fraction, 1.0)
    }

    private var formattedTokenCount: String {
        let tokens = metadata.estimatedTokenCount
        if tokens >= 1_000 {
            return String(format: "%.1fk", Double(tokens) / 1_000)
        }
        return "\(tokens)"
    }

    private var abbreviatedDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = metadata.workingDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var formattedDuration: String {
        let secs = Int(metadata.sessionDuration)
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        let remainSecs = secs % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        } else if mins > 0 {
            return "\(mins)m \(remainSecs)s"
        } else {
            return "\(remainSecs)s"
        }
    }
}

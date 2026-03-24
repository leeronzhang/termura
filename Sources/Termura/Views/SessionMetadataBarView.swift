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
                VStack(alignment: .leading, spacing: AppUI.Spacing.lgXl) {
                    if metadata.currentAgentType != nil {
                        agentSection
                    }
                    directorySection
                    tokenSection
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
                    Text(agentType.rawValue)
                        .font(AppUI.Font.bodyMedium)
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
            } else {
                Text(formattedTokenCount)
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
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

    // MARK: - Reusable item layout

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

    // MARK: - Computed

    private var formattedTokenCount: String {
        let tokens = metadata.estimatedTokenCount
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
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

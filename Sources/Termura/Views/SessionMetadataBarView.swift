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
                VStack(alignment: .leading, spacing: 16) {
                    directorySection
                    tokenSection
                    commandSection
                    durationSection
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }

    // MARK: - Header

    private var panelHeader: some View {
        Text("Session")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
    }

    // MARK: - Directory

    private var directorySection: some View {
        metadataItem(label: "Directory") {
            Text(abbreviatedDirectory)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
                .help(metadata.workingDirectory)
        }
    }

    // MARK: - Tokens

    private var tokenSection: some View {
        metadataItem(label: "Tokens") {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: tokenFraction, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(tokenFraction >= AppConfig.UI.tokenProgressWarningFraction ? .orange : .accentColor)
                Text(formattedTokenCount)
                    .font(.system(size: 11))
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
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
    }

    // MARK: - Duration

    private var durationSection: some View {
        metadataItem(label: "Duration") {
            Text(formattedDuration)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
        }
    }

    // MARK: - Reusable item layout

    @ViewBuilder
    private func metadataItem<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
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

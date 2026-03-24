import SwiftUI

/// Narrow vertical panel showing the session's command history as a scrollable timeline.
/// Tapping a turn scrolls the output view to the corresponding chunk.
struct TimelineView: View {
    @ObservedObject var timeline: SessionTimeline
    let onSelectChunkID: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AppUI.Spacing.xxs) {
                    ForEach(timeline.turns) { turn in
                        TimelineTurnRow(turn: turn) {
                            onSelectChunkID(turn.chunkID)
                        }
                        ForEach(turn.branchPoints) { marker in
                            BranchPointIndicator(marker: marker)
                        }
                    }
                }
                .padding(.vertical, AppUI.Spacing.smMd)
                .padding(.horizontal, AppUI.Spacing.sm)
            }
        }
        .frame(width: AppConfig.Timeline.panelWidth)
        .background(.ultraThinMaterial)
    }

    private var headerBar: some View {
        Text("Timeline")
            .panelHeaderStyle()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppUI.Spacing.lg)
            .padding(.vertical, AppUI.Spacing.mdLg)
    }
}

// MARK: - Turn Row

private struct TimelineTurnRow: View {
    let turn: TimelineTurn
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: AppUI.Spacing.smMd) {
                exitIndicator
                VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                    commandLabel
                    Text(turn.startedAt, style: .time)
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.vertical, AppUI.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverRow(isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var exitIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: AppUI.Size.dotMediumSmall, height: AppUI.Size.dotMediumSmall)
    }

    private var commandLabel: some View {
        Text(turn.command.isEmpty ? "(no command)" : turn.command)
            .font(AppUI.Font.labelMono)
            .foregroundColor(labelColor)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var indicatorColor: Color {
        guard let code = turn.exitCode else { return .gray }
        return code == 0 ? .green : .red
    }

    private var labelColor: Color {
        guard let code = turn.exitCode, code != 0 else { return .primary }
        return .red
    }
}

// MARK: - Branch Point Indicator

private struct BranchPointIndicator: View {
    let marker: BranchPointMarker

    var body: some View {
        HStack(spacing: AppUI.Spacing.sm) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(marker.branchType.rawValue.capitalized)
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
        }
        .padding(.leading, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.xxs)
    }
}

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
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(timeline.turns) { turn in
                        TimelineTurnRow(turn: turn) {
                            onSelectChunkID(turn.chunkID)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .frame(width: AppConfig.Timeline.panelWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var headerBar: some View {
        Text("Timeline")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
    }
}

// MARK: - Turn Row

private struct TimelineTurnRow: View {
    let turn: TimelineTurn
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                exitIndicator
                VStack(alignment: .leading, spacing: 1) {
                    commandLabel
                    Text(turn.startedAt, style: .time)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered
                    ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.15)
                    : Color.clear
            )
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private var exitIndicator: some View {
        Circle()
            .fill(indicatorColor)
            .frame(width: 6, height: 6)
    }

    private var commandLabel: some View {
        Text(turn.command.isEmpty ? "(no command)" : turn.command)
            .font(.system(size: 11, design: .monospaced))
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

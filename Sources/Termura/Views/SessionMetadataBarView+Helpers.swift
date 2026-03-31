import SwiftUI

// MARK: - Activity Section

extension SessionMetadataBarView {
    @ViewBuilder
    var activitySection: some View {
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
                    if isClearCommand(turn.command) {
                        clearDividerRow(at: turn.startedAt)
                    } else {
                        Button { onSelectChunkID?(turn.chunkID) } label: {
                            HStack(spacing: AppUI.Spacing.smMd) {
                                Circle().fill(exitCodeColor(turn.exitCode))
                                    .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                                Image(systemName: contentTypeIcon(turn.contentType))
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                Text(turnLabel(turn)).font(AppUI.Font.captionMono)
                                    .lineLimit(1).foregroundColor(.primary)
                                Spacer()
                                if let dur = turn.duration {
                                    Text(formattedDuration(dur)).font(AppUI.Font.micro)
                                        .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
                                        .monospacedDigit()
                                }
                                Text(formattedTime(turn.startedAt)).font(AppUI.Font.micro)
                                    .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
                            }.padding(.vertical, AppUI.Spacing.xs)
                        }
                        .buttonStyle(.plain)
                        .disabled(turn.startLine == nil)
                    }
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
}

// MARK: - Helpers

extension SessionMetadataBarView {
    func turnLabel(_ turn: TimelineTurn) -> String {
        if !turn.command.isEmpty { return turn.command }
        guard let tl = timeline else { return "Turn" }
        let idx = tl.turns.firstIndex(where: { $0.id == turn.id }).map { $0 + 1 } ?? 0
        return "Turn \(idx)"
    }

    func agentStatusColor(_ status: AgentStatus) -> Color {
        switch status {
        case .idle: .secondary
        case .thinking: .blue
        case .toolRunning: .orange
        case .waitingInput: .yellow
        case .error: .red
        case .completed: .green
        }
    }

    func exitCodeColor(_ code: Int?) -> Color {
        guard let code else { return .secondary }
        return code == 0 ? .green : .red
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func formattedDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "<1s" }
        if seconds < 60 { return "\(Int(seconds))s" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return secs == 0 ? "\(mins)m" : "\(mins)m\(secs)s"
    }

    func isClearCommand(_ command: String) -> Bool {
        command.trimmingCharacters(in: .whitespaces) == "clear"
    }

    @ViewBuilder
    func clearDividerRow(at date: Date) -> some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            Rectangle()
                .fill(Color.secondary.opacity(AppUI.Opacity.whisper))
                .frame(height: 1)
            Text("cleared \(formattedTime(date))")
                .font(AppUI.Font.micro)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(AppUI.Opacity.whisper))
                .frame(height: 1)
        }
        .padding(.vertical, AppUI.Spacing.smMd)
    }

    func contentTypeIcon(_ type: OutputContentType) -> String {
        switch type {
        case .toolCall:      return "wrench"
        case .diff:          return "arrow.left.arrow.right"
        case .error:         return "xmark.circle"
        case .code:          return "chevron.left.forwardslash.chevron.right"
        case .text:          return "text.alignleft"
        case .commandOutput: return "terminal"
        }
    }
}

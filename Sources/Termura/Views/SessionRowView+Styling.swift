import SwiftUI

extension SessionRowView {
    var accessibilityStatusValue: String {
        var parts: [String] = []
        if isActive {
            parts.append("Active")
        } else if isInSplit {
            parts.append("In split view")
        } else if isInNonActiveSplit {
            parts.append("In split view (inactive tab)")
        } else if session.isEnded {
            parts.append("Ended")
        }
        if let type = agentType, type != .unknown { parts.append(type.displayName) }
        if let status = agentStatus { parts.append(status.rawValue) }
        if let tokens = tokenSummary { parts.append("\(tokens) tokens") }
        if let duration = durationText { parts.append(duration) }
        return parts.joined(separator: ", ")
    }

    var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppUI.Radius.md)
            .fill(rowFillColor)
    }

    var rowFillColor: Color {
        if isActive {
            return Color.brandGreen.opacity(AppUI.Opacity.selected)
        } else if isInSplit {
            return Color.brandGreen.opacity(AppUI.Opacity.whisper)
        } else if isHovered {
            return themeManager.current.sidebarText.opacity(AppUI.Opacity.whisper)
        }
        // Non-active splits use a left bar indicator instead of background fill.
        return .clear
    }

    var glowBorder: some View {
        let borderColor = if isActive {
            Color.brandGreen.opacity(AppUI.Opacity.border)
        } else if isInSplit {
            Color.brandGreen.opacity(AppUI.Opacity.whisper)
        } else {
            Color.brandGreen.opacity(glowOpacity)
        }
        return RoundedRectangle(cornerRadius: AppUI.Radius.md)
            .stroke(borderColor, lineWidth: 1)
    }

    /// Left-edge accent bar for sessions in a non-active split tab.
    var splitIndicatorBar: some View {
        Group {
            if isInNonActiveSplit {
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.brandGreen.opacity(AppUI.Opacity.secondary))
                        .frame(width: 2)
                        .padding(.vertical, AppUI.Spacing.sm)
                    Spacer()
                }
            }
        }
    }

    func colorForLabel(_ label: SessionColorLabel) -> Color {
        switch label {
        case .none: .clear
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        }
    }

    /// Distinct hue for each split-pair group so users can visually associate
    /// paired sessions in the sidebar. Cycles through the palette by index.
    /// Red is reserved for failure dots; these hues are chosen to be visually
    /// distinguishable from each other and from the agent/status icons.
    static let splitGroupPalette: [Color] = [
        .brandGreen, .blue, .orange, .purple, .pink, .cyan
    ]

    func colorForSplitGroup(_ groupIndex: Int) -> Color {
        let palette = Self.splitGroupPalette
        return palette[((groupIndex % palette.count) + palette.count) % palette.count]
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Session Rows") {
    VStack(spacing: 4) {
        SessionRowView(
            session: SessionRecord(title: "feat: add preview support", workingDirectory: "~/termura"),
            isActive: true,
            hasUnreadFailure: false,
            agentStatus: .thinking,
            agentType: .claudeCode,
            tokenSummary: "42.1k",
            durationText: "4m 23s",
            currentTaskSnippet: "Writing preview macros",
            onActivate: {},
            onRename: { _ in }
        )
        SessionRowView(
            session: SessionRecord(title: "fix: cursor positioning", workingDirectory: "~/project"),
            isActive: false,
            hasUnreadFailure: false,
            agentStatus: .toolRunning,
            agentType: .codex,
            tokenSummary: "12.3k",
            durationText: "1m 05s",
            onActivate: {},
            onRename: { _ in }
        )
        SessionRowView(
            session: SessionRecord(title: "Terminal Session"),
            isActive: false, hasUnreadFailure: true,
            onActivate: {}, onRename: { _ in }
        )
        SessionRowView(
            session: SessionRecord(title: "Archived session", status: .ended(at: Date())),
            isActive: false, hasUnreadFailure: false,
            agentStatus: .completed, agentType: .gemini,
            tokenSummary: "88.0k", durationText: "12m 41s",
            onActivate: {}, onRename: { _ in }
        )
    }
    .frame(width: 260)
    .padding()
}
#endif

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
            return Color.accentColor.opacity(AppUI.Opacity.selected)
        } else if isInSplit {
            return Color.accentColor.opacity(AppUI.Opacity.whisper)
        } else if isHovered {
            return themeManager.current.sidebarText.opacity(AppUI.Opacity.whisper)
        }
        // Non-active splits use a left bar indicator instead of background fill.
        return .clear
    }

    var glowBorder: some View {
        let borderColor = if isActive {
            Color.accentColor.opacity(AppUI.Opacity.border)
        } else if isInSplit {
            Color.accentColor.opacity(AppUI.Opacity.whisper)
        } else {
            Color.accentColor.opacity(glowOpacity)
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
                        .fill(Color.accentColor.opacity(AppUI.Opacity.secondary))
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
}

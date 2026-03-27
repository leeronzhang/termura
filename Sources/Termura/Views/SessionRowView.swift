import SwiftUI

/// A single row in the session sidebar.
struct SessionRowView: View {
    let session: SessionRecord
    let isActive: Bool
    /// True when the session is in a dual-pane split but not the focused pane.
    var isInSplit: Bool = false
    let hasUnreadFailure: Bool
    var agentStatus: AgentStatus?
    var agentType: AgentType?
    /// Formatted token count (e.g. "42.1k") for the session, if available.
    var tokenSummary: String?
    /// Formatted duration (e.g. "4m 23s") for the session, if available.
    var durationText: String?
    /// Brief description of agent's current task.
    var currentTaskSnippet: String?
    let onActivate: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void
    /// Optional toggle for expand/collapse. When set, a chevron is shown.
    var onToggleExpand: (() -> Void)?
    var isExpanded: Bool = true

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovered = false
    @State private var glowOpacity: Double = 0.0
    @State private var showCloseConfirm = false
    @Environment(\.themeManager) private var themeManager

    private var isWaiting: Bool { agentStatus == .waitingInput }

    var body: some View {
        HStack(alignment: .top, spacing: AppUI.Spacing.smMd) {
            leadingIcons
            VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
                titleRow
                agentStatsLine
            }
        }
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.vertical, AppUI.Spacing.md)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(glowBorder)
        .onTapGesture { onActivate() }
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session: \(session.title)")
        .accessibilityValue(isActive ? "Active" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu { contextMenuItems }
        .animation(.easeOut(duration: AppUI.Animation.quick), value: isHovered)
        .onChange(of: isWaiting) { _, waiting in
            if waiting {
                withAnimation(
                    .easeInOut(duration: AppConfig.Agent.glowAnimationDuration)
                        .repeatForever(autoreverses: true)
                ) {
                    glowOpacity = AppUI.Opacity.secondary
                }
            } else {
                withAnimation(.easeOut(duration: AppUI.Animation.fadeOut)) {
                    glowOpacity = 0.0
                }
            }
        }
    }

    @ViewBuilder
    private var leadingIcons: some View {
        if let type = agentType, type != .unknown {
            AgentIconView(agentType: type, size: 14, isActive: agentStatus != nil)
                .padding(.top, AppUI.Spacing.xxs)
        } else if session.colorLabel != .none {
            Circle()
                .fill(colorForLabel(session.colorLabel))
                .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
                .padding(.top, AppUI.Spacing.xxs)
        }
    }

    private var titleRow: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            titleLabel
            Spacer(minLength: AppUI.Spacing.sm)
            if hasUnreadFailure {
                Circle()
                    .fill(Color.red)
                    .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
            }
            if let toggle = onToggleExpand {
                Button {
                    toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(AppUI.Font.micro)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
                        .frame(width: AppUI.Size.iconFrame, height: AppUI.Size.iconFrame)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            closeButton
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var titleLabel: some View {
        if isEditing {
            TextField("Session name", text: $editTitle, onCommit: commitEdit)
                .textFieldStyle(.plain)
                .font(AppUI.Font.title3)
                .foregroundColor(themeManager.current.sidebarText)
                .onExitCommand { cancelEdit() }
        } else {
            Text(session.title)
                .font((isActive || isInSplit) ? AppUI.Font.title3Medium : AppUI.Font.title3)
                .foregroundColor((isActive || isInSplit) ? .primary : themeManager.current.sidebarText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var agentStatsLine: some View {
        let hasAgent = agentStatus != nil
        if hasAgent {
            HStack(spacing: AppUI.Spacing.smMd) {
                if let status = agentStatus, let type = agentType {
                    AgentStatusBadgeView(status: status, agentType: type)
                }
                if let status = agentStatus {
                    Text(MetadataFormatter.formatAgentStatus(status))
                        .font(AppUI.Font.labelMono)
                        .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.secondary))
                        .lineLimit(1)
                }
                Spacer(minLength: AppUI.Spacing.sm)
                HStack(spacing: AppUI.Spacing.smMd) {
                    if let tokens = tokenSummary {
                        compactLabel(tokens, icon: "text.word.spacing")
                    }
                    if let duration = durationText {
                        compactLabel(duration, icon: "clock")
                    }
                }
                .monospacedDigit()
            }
        } else if session.agentType != .unknown {
            // Previous agent session -- show persisted type
            Text(session.agentType.displayName)
                .font(AppUI.Font.captionMono)
                .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.tertiary))
        }
    }

    private func compactLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: AppUI.Spacing.xxs) {
            Image(systemName: icon)
                .font(AppUI.Font.micro)
            Text(text)
                .font(AppUI.Font.captionMono)
        }
        .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.tertiary))
    }

    private var closeButton: some View {
        Button {
            if isActive {
                showCloseConfirm = true
            } else {
                onClose()
            }
        } label: {
            Image(systemName: "xmark")
                .font(AppUI.Font.micro)
                .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.tertiary))
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0)
        .alert("Close Active Session?", isPresented: $showCloseConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Stop & Close", role: .destructive) { onClose() }
        } message: {
            Text("This session is currently active. The running process will be terminated.")
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: AppUI.Radius.md)
            .fill(rowFillColor)
    }

    private var rowFillColor: Color {
        if isActive {
            return Color.accentColor.opacity(AppUI.Opacity.selected)
        } else if isInSplit {
            return Color.accentColor.opacity(AppUI.Opacity.whisper)
        } else if isHovered {
            return themeManager.current.sidebarText.opacity(AppUI.Opacity.whisper)
        }
        return .clear
    }

    private var glowBorder: some View {
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

    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Rename") { beginEditing() }
        Divider()
        Button("Close Session", role: .destructive) { onClose() }
    }

    // MARK: - Edit helpers

    private func beginEditing() {
        editTitle = session.title
        isEditing = true
    }

    private func commitEdit() {
        isEditing = false
        let trimmed = editTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onRename(trimmed)
    }

    private func cancelEdit() {
        isEditing = false
    }

    private func colorForLabel(_ label: SessionColorLabel) -> Color {
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

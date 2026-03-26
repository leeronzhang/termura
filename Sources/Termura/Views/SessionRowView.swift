import SwiftUI

/// A single row in the session sidebar.
struct SessionRowView: View {
    let session: SessionRecord
    let isActive: Bool
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
    @EnvironmentObject private var themeManager: ThemeManager

    private var isWaiting: Bool { agentStatus == .waitingInput }

    var body: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            sessionInfo
            Spacer(minLength: AppUI.Spacing.sm)
            actionButtons
            closeButton
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.smMd)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(glowBorder)
        .onTapGesture { onActivate() }
        .onHover { isHovered = $0 }
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
    private var sessionInfo: some View {
        colorDot
        if let type = agentType, type != .unknown {
            AgentIconView(agentType: type, size: 14, isActive: agentStatus != nil)
        }
        sessionTitle
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let status = agentStatus, let type = agentType {
            AgentStatusBadgeView(status: status, agentType: type)
        }
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
    }

    // MARK: - Subviews

    @ViewBuilder
    private var colorDot: some View {
        if session.colorLabel != .none {
            Circle()
                .fill(colorForLabel(session.colorLabel))
                .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
        }
    }

    @ViewBuilder
    private var sessionTitle: some View {
        if isEditing {
            TextField("Session name", text: $editTitle, onCommit: commitEdit)
                .textFieldStyle(.plain)
                .font(AppUI.Font.title3)
                .foregroundColor(themeManager.current.sidebarText)
                .onExitCommand { cancelEdit() }
        } else {
            VStack(alignment: .leading, spacing: AppUI.Spacing.xs) {
                Text(session.title)
                    .font(isActive ? AppUI.Font.title3Medium : AppUI.Font.title3)
                    .foregroundColor(isActive ? .primary : themeManager.current.sidebarText)
                    .lineLimit(1)
                if let dir = workingDirectorySubtitle {
                    Text(dir)
                        .font(AppUI.Font.caption)
                        .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.tertiary))
                        .lineLimit(1)
                }
                agentStatsLine
            }
        }
    }

    @ViewBuilder
    private var agentStatsLine: some View {
        let parts = [
            agentStatus.map { MetadataFormatter.formatAgentStatus($0) },
            tokenSummary,
            durationText
        ].compactMap { $0 }
        if !parts.isEmpty {
            Text(parts.joined(separator: "  "))
                .font(AppUI.Font.captionMono)
                .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.tertiary))
                .lineLimit(1)
        }
    }

    private var workingDirectorySubtitle: String? {
        let path = session.workingDirectory
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
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
        } else if isHovered {
            return themeManager.current.sidebarText.opacity(AppUI.Opacity.whisper)
        }
        return .clear
    }

    private var glowBorder: some View {
        RoundedRectangle(cornerRadius: AppUI.Radius.md)
            .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : Color.accentColor.opacity(glowOpacity), lineWidth: 1)
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

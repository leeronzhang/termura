import SwiftUI

/// A single row in the session sidebar.
struct SessionRowView: View {
    let session: SessionRecord
    let isActive: Bool
    /// True when the session is in a dual-pane split but not the focused pane.
    var isInSplit: Bool = false
    /// True when the session is in a split tab that is not currently selected.
    var isInNonActiveSplit: Bool = false
    /// Split membership info — partner name, slot, active state.
    var splitInfo: SplitMembership?
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
    /// Optional toggle for expand/collapse. When set, a chevron is shown.
    var onToggleExpand: (() -> Void)?
    var isExpanded: Bool = true
    /// Increment this value from outside to trigger inline rename. Each increment fires once.
    var renameTrigger: Int = 0

    @State private var isEditing = false
    @State private var editTitle = ""
    @State var isHovered = false
    @State var glowOpacity: Double = 0.0
    @Environment(\.themeManager) var themeManager

    var isWaiting: Bool { agentStatus == .waitingInput }

    var body: some View {
        HStack(alignment: .top, spacing: AppUI.Spacing.smMd) {
            leadingIcons
            VStack(alignment: .leading, spacing: AppUI.Spacing.smMd) {
                titleRow
                splitPartnerLine
                agentStatsLine
            }
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
        .opacity(session.isEnded ? AppUI.Opacity.secondary : 1.0)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppUI.Radius.md))
        .overlay(splitIndicatorBar)
        .overlay(glowBorder)
        .onTapGesture { onActivate() }
        .onHover { isHovered = $0 }
        .draggable(session.id.rawValue.uuidString)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session: \(session.title)")
        .accessibilityValue(accessibilityStatusValue)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("sessionRow")
        .onChange(of: renameTrigger) { _, _ in beginEditing() }
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
        VStack(spacing: AppUI.Spacing.xxs) {
            if let type = agentType, type != .unknown {
                AgentIconView(agentType: type, size: 14, isActive: agentStatus != nil)
            } else if session.colorLabel != .none {
                Circle()
                    .fill(colorForLabel(session.colorLabel))
                    .frame(width: AppUI.Size.dotMedium, height: AppUI.Size.dotMedium)
            } else if let type = agentType {
                AgentIconView(agentType: type, size: 14, isActive: agentStatus != nil)
            }
            if splitInfo != nil {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 9))
                    .foregroundColor(.brandGreen.opacity(
                        (isActive || isInSplit) ? AppUI.Opacity.strong : AppUI.Opacity.tertiary
                    ))
            }
        }
        .padding(.top, AppUI.Spacing.xxs)
    }

    private var titleRow: some View {
        HStack(spacing: AppUI.Spacing.smMd) {
            titleLabel
            Spacer(minLength: 0)
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
                .accessibilityLabel(isExpanded ? "Collapse branches" : "Expand branches")
            }
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
            let visibleTitle = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayTitle = visibleTitle.isEmpty
                ? (agentType?.displayName ?? "Terminal")
                : session.title
            Text(displayTitle)
                .font((isActive || isInSplit) ? AppUI.Font.title3Medium : AppUI.Font.title3)
                .foregroundColor((isActive || isInSplit) ? .primary : themeManager.current.sidebarText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var splitPartnerLine: some View {
        if let info = splitInfo {
            HStack(spacing: AppUI.Spacing.xxs) {
                Image(systemName: "link")
                    .font(.system(size: 8))
                Text(info.partnerTitle)
                    .lineLimit(1)
            }
            .font(AppUI.Font.captionMono)
            .foregroundColor(.secondary.opacity(AppUI.Opacity.tertiary))
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
        } else {
            // Show persisted type (or "Terminal" for .unknown) as placeholder.
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
}

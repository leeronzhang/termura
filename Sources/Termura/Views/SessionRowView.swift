import SwiftUI

/// A single row in the session sidebar.
struct SessionRowView: View {
    let session: SessionRecord
    let isActive: Bool
    let hasUnreadFailure: Bool
    var agentStatus: AgentStatus?
    var agentType: AgentType?
    let onActivate: () -> Void
    let onRename: (String) -> Void
    let onClose: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovered = false
    @State private var glowOpacity: Double = 0.0
    @EnvironmentObject private var themeManager: ThemeManager

    private var isWaiting: Bool { agentStatus == .waitingInput }

    var body: some View {
        HStack(spacing: DS.Spacing.smMd) {
            colorDot
            sessionTitle
            Spacer(minLength: DS.Spacing.sm)
            if let status = agentStatus, let type = agentType {
                AgentStatusBadgeView(status: status, agentType: type)
            }
            if hasUnreadFailure {
                Circle()
                    .fill(Color.red)
                    .frame(width: DS.Size.dotMedium, height: DS.Size.dotMedium)
            }
            closeButton
        }
        .padding(.horizontal, DS.Spacing.mdLg)
        .padding(.vertical, DS.Spacing.smMd)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(glowBorder)
        .onTapGesture(count: 2) { beginEditing() }
        .onTapGesture(count: 1) { onActivate() }
        .onHover { isHovered = $0 }
        .contextMenu { contextMenuItems }
        .animation(.easeOut(duration: DS.Animation.quick), value: isHovered)
        .onChange(of: isWaiting) { _, waiting in
            if waiting {
                withAnimation(
                    .easeInOut(duration: AppConfig.Agent.glowAnimationDuration)
                    .repeatForever(autoreverses: true)
                ) {
                    glowOpacity = DS.Opacity.secondary
                }
            } else {
                withAnimation(.easeOut(duration: DS.Animation.fadeOut)) {
                    glowOpacity = 0.0
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var colorDot: some View {
        if session.colorLabel != .none {
            Circle()
                .fill(colorForLabel(session.colorLabel))
                .frame(width: DS.Size.dotMedium, height: DS.Size.dotMedium)
        }
    }

    @ViewBuilder
    private var sessionTitle: some View {
        if isEditing {
            TextField("Session name", text: $editTitle, onCommit: commitEdit)
                .textFieldStyle(.plain)
                .font(DS.Font.title3)
                .foregroundColor(themeManager.current.sidebarText)
                .onExitCommand { cancelEdit() }
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(session.title)
                    .font(DS.Font.title3)
                    .foregroundColor(themeManager.current.sidebarText)
                    .lineLimit(1)
                if let dir = workingDirectorySubtitle {
                    Text(dir)
                        .font(DS.Font.caption)
                        .foregroundColor(themeManager.current.sidebarText.opacity(DS.Opacity.tertiary))
                        .lineLimit(1)
                }
            }
        }
    }

    private var workingDirectorySubtitle: String? {
        let path = session.workingDirectory
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(DS.Font.micro)
                .foregroundColor(themeManager.current.sidebarText.opacity(DS.Opacity.tertiary))
        }
        .buttonStyle(.plain)
        .opacity(isActive || isHovered ? 1 : 0)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.Radius.md)
            .fill(rowFillColor)
    }

    private var rowFillColor: Color {
        if isActive {
            return themeManager.current.activeSessionHighlight.opacity(DS.Opacity.selected)
        } else if isHovered {
            return themeManager.current.sidebarText.opacity(DS.Opacity.whisper)
        }
        return .clear
    }

    private var glowBorder: some View {
        RoundedRectangle(cornerRadius: DS.Radius.md)
            .stroke(Color.accentColor.opacity(glowOpacity), lineWidth: 1)
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

import AppKit
import SwiftUI

// MARK: - Sessions Tab

extension SidebarView {
    var sessionsContent: some View {
        VStack(spacing: 0) {
            sessionsHeader
            sessionList
        }
    }

    private var sessionsHeader: some View {
        HStack {
            Text("Sessions")
                .panelHeaderStyle()
            Spacer()
            Button { sessionStore.createSession(title: "Terminal") } label: {
                Image(systemName: "plus")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.xxxl)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var pinnedSessions: [SessionRecord] {
        sessionStore.sessions.filter(\.isPinned)
    }

    private var treeNodes: [SessionTreeNode] {
        SessionTreeNode.buildForest(from: sessionStore.sessions)
    }

    var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: AppUI.Spacing.xs) {
                if !pinnedSessions.isEmpty {
                    sectionLabel("Pinned")
                    ForEach(pinnedSessions) { session in
                        sessionRow(session)
                    }
                    sectionLabel("Sessions")
                }
                ForEach(treeNodes) { node in
                    SidebarTreeNodeView(
                        node: node,
                        sessionStore: sessionStore,
                        sessionRow: { session, toggleExpand, expanded in
                            AnyView(sessionRow(session, toggleExpand: toggleExpand, isExpanded: expanded))
                        }
                    )
                }
            }
            .padding(.horizontal, AppUI.Spacing.lg)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .sectionLabelStyle()
            .padding(.horizontal, AppUI.Spacing.md)
            .padding(.top, AppUI.Spacing.lg)
            .padding(.bottom, AppUI.Spacing.sm)
    }

    func sessionRow(
        _ session: SessionRecord,
        toggleExpand: (() -> Void)? = nil,
        isExpanded: Bool = true
    ) -> some View {
        SessionRowView(
            session: session,
            isActive: sessionStore.activeSessionID == session.id
                && activeContentTab?.sessionID == session.id,
            hasUnreadFailure: false,
            agentStatus: projectContext.agentStateStore.agents[session.id]?.status,
            agentType: projectContext.agentStateStore.agents[session.id]?.agentType ?? session.agentType,
            onActivate: { sessionStore.activateSession(id: session.id) },
            onRename: { sessionStore.renameSession(id: session.id, title: $0) },
            onClose: { sessionStore.closeSession(id: session.id) },
            onToggleExpand: toggleExpand,
            isExpanded: isExpanded
        )
        .contextMenu {
            branchMenu(for: session)
            Divider()
            if session.isPinned {
                Button("Unpin") { sessionStore.unpinSession(id: session.id) }
            } else {
                Button("Pin") { sessionStore.pinSession(id: session.id) }
            }
            Divider()
            colorLabelMenu(for: session)
            Divider()
            Button("Export\u{2026}") {
                commandRouter.requestExport(sessionID: session.id)
            }
            Divider()
            Button("Close Session", role: .destructive) {
                sessionStore.closeSession(id: session.id)
            }
        }
    }

    @ViewBuilder
    func branchMenu(for session: SessionRecord) -> some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    Task { await sessionStore.createBranch(from: session.id, type: type) }
                }
            }
        }
        if session.parentID != nil {
            Button("Back to Parent") {
                sessionStore.navigateToParent(of: session.id)
            }
        }
    }

    func colorLabelMenu(for session: SessionRecord) -> some View {
        Menu("Color Label") {
            ForEach(SessionColorLabel.allCases, id: \.self) { label in
                Button(label.rawValue.capitalized) {
                    sessionStore.setColorLabel(id: session.id, label: label)
                }
            }
        }
    }

    var sessionFooter: some View {
        HStack {
            Spacer()
            Button {
                sessionStore.createSession(title: "Terminal")
            } label: {
                Image(systemName: "plus")
                    .font(AppUI.Font.title2)
                    .foregroundColor(themeManager.current.sidebarText.opacity(AppUI.Opacity.dimmed))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            Spacer()
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.lg)
    }
}

// MARK: - Agents Tab

extension SidebarView {
    @ViewBuilder
    var agentsContent: some View {
        AgentDashboardView(agentStore: projectContext.agentStateStore) { sid in
            sessionStore.activateSession(id: sid)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared Empty State

extension SidebarView {
    func sidebarEmptyState(icon: String, message: String) -> some View {
        VStack(spacing: AppUI.Spacing.smMd) {
            Image(systemName: icon)
                .font(AppUI.Font.hero)
                .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
            Text(message)
                .font(AppUI.Font.label)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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

    var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: AppUI.Spacing.sm) {
                if !sessionStore.pinnedSessions.isEmpty {
                    sectionLabel("Pinned")
                    ForEach(sessionStore.pinnedSessions) { session in
                        sessionRow(session)
                    }
                    sectionLabel("Sessions")
                }
                ForEach(sessionStore.sessionTreeNodes) { node in
                    SidebarTreeNodeView(
                        node: node,
                        sessionStore: sessionStore,
                        sessionRow: { session, toggleExpand, expanded in
                            AnyView(sessionRow(session, toggleExpand: toggleExpand, isExpanded: expanded))
                        }
                    )
                }
                // Ended sessions — no section header, visually dimmed via SessionRowView.
                ForEach(sessionStore.endedSessions) { session in
                    sessionRow(session)
                }
            }
            .padding(.horizontal, AppUI.Spacing.lg)
        }
        .alert("Delete Session?", isPresented: Binding(
            get: { sessionPendingDelete != nil },
            set: { if !$0 { sessionPendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { sessionPendingDelete = nil }
            Button("Delete", role: .destructive) {
                guard let sid = sessionPendingDelete else { return }
                sessionPendingDelete = nil
                Task { await sessionStore.deleteSession(id: sid) }
            }
        } message: {
            Text("This session and all its history will be permanently removed.")
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
        let agentState = sessionScope.agentStates.agents[session.id]
        let tokens: String? = {
            guard let tokenTotal = agentState?.tokenCount, tokenTotal > 0 else { return nil }
            return MetadataFormatter.formatTokenCount(tokenTotal)
        }()
        let duration: String? = {
            guard let started = agentState?.startedAt else { return nil }
            let elapsed = sessionScope.agentStates.now.timeIntervalSince(started)
            guard elapsed > 0 else { return nil }
            return MetadataFormatter.formatDuration(elapsed)
        }()
        let isInCurrentTab = activeContentTab?.containsSession(session.id) ?? false
        let isFocused = focusedSessionID == session.id
        let activeState = isInCurrentTab && isFocused
        let splitState = isInCurrentTab && !isFocused
        return SessionRowView(
            session: session,
            isActive: activeState,
            isInSplit: splitState,
            hasUnreadFailure: false,
            agentStatus: agentState?.status,
            agentType: agentState?.agentType ?? session.agentType,
            tokenSummary: tokens,
            durationText: duration,
            currentTaskSnippet: agentState?.currentTask,
            onActivate: { activateOrSplit(session: session) },
            onRename: { sessionStore.renameSession(id: session.id, title: $0) },
            onToggleExpand: toggleExpand,
            isExpanded: isExpanded,
            renameTrigger: renameTriggers[session.id, default: 0]
        )
        .contextMenu { sessionContextMenu(for: session) }
    }

    @ViewBuilder
    func sessionContextMenu(for session: SessionRecord) -> some View {
        Button("Rename") { renameTriggers[session.id, default: 0] += 1 }
        Divider()
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
        if session.isEnded {
            Button("Reopen") {
                Task { await sessionStore.reopenSession(id: session.id) }
            }
        } else {
            Button("End Session") {
                commandRouter.pendingCommand = .endSession(session.id)
            }
        }
        Divider()
        Button("Delete\u{2026}", role: .destructive) {
            sessionPendingDelete = session.id
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

    /// Delegates to MainView which handles find-existing-tab-or-open-new logic.
    private func activateOrSplit(session: SessionRecord) {
        onActivateSession?(session)
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
        AgentDashboardView(
            agentStore: sessionScope.agentStates,
            sessionTitles: sessionStore.sessionTitles
        ) { sid in
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

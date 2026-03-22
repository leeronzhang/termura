import SwiftUI

/// Vertical session list sidebar with pinned sections and drag-to-reorder.
struct SidebarView: View {
    @ObservedObject var sessionStore: SessionStore
    @EnvironmentObject private var themeManager: ThemeManager

    private var pinnedSessions: [SessionRecord] {
        sessionStore.sessions.filter(\.isPinned)
    }

    private var regularSessions: [SessionRecord] {
        sessionStore.sessions.filter { !$0.isPinned }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            sessionList
            Divider()
            footer
        }
        .frame(minWidth: AppConfig.UI.sidebarMinWidth, maxWidth: AppConfig.UI.sidebarMaxWidth)
        .background(themeManager.current.sidebarBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Sessions")
                .panelHeaderStyle()
                .foregroundColor(themeManager.current.sidebarText.opacity(DS.Opacity.tertiary))
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.smMd)
    }

    // MARK: - Session list

    private var treeNodes: [SessionTreeNode] {
        SessionTreeNode.buildForest(from: sessionStore.sessions)
    }

    private var sessionList: some View {
        List {
            if !pinnedSessions.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedSessions) { session in
                        sessionRow(session)
                    }
                    .onMove { from, to in
                        sessionStore.reorderSessions(from: from, to: to)
                    }
                }
            }
            Section(pinnedSessions.isEmpty ? "" : "Sessions") {
                ForEach(treeNodes) { node in
                    treeNodeRow(node)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func treeNodeRow(_ node: SessionTreeNode) -> some View {
        SidebarTreeNodeView(
            node: node,
            sessionStore: sessionStore,
            sessionRow: { session in AnyView(sessionRow(session)) }
        )
    }

    private func sessionRow(_ session: SessionRecord) -> some View {
        SessionRowView(
            session: session,
            isActive: sessionStore.activeSessionID == session.id,
            hasUnreadFailure: false,
            onActivate: { sessionStore.activateSession(id: session.id) },
            onRename: { sessionStore.renameSession(id: session.id, title: $0) },
            onClose: { sessionStore.closeSession(id: session.id) }
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
                NotificationCenter.default.post(
                    name: .showExport,
                    object: session.id
                )
            }
            Divider()
            Button("Close Session", role: .destructive) {
                sessionStore.closeSession(id: session.id)
            }
        }
    }

    @ViewBuilder
    private func branchMenu(for session: SessionRecord) -> some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    Task {
                        await sessionStore.createBranch(from: session.id, type: type)
                    }
                }
            }
        }
        if session.parentID != nil {
            Button("Back to Parent") {
                sessionStore.navigateToParent(of: session.id)
            }
        }
    }

    private func colorLabelMenu(for session: SessionRecord) -> some View {
        Menu("Color Label") {
            ForEach(SessionColorLabel.allCases, id: \.self) { label in
                Button(label.rawValue.capitalized) {
                    sessionStore.setColorLabel(id: session.id, label: label)
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                sessionStore.createSession(title: "Terminal")
            } label: {
                Image(systemName: "plus")
                    .font(DS.Font.title2)
                    .foregroundColor(themeManager.current.sidebarText.opacity(DS.Opacity.dimmed))
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(themeManager.current.sidebarBackground)
    }
}

// MARK: - Recursive tree node (breaks opaque return type cycle)

private struct SidebarTreeNodeView: View {
    let node: SessionTreeNode
    let sessionStore: SessionStore
    let sessionRow: (SessionRecord) -> AnyView

    var body: some View {
        if !node.record.isPinned {
            HStack(spacing: 0) {
                if node.depth > 0 {
                    BranchIndicatorView(
                        depth: node.depth,
                        branchType: node.record.branchType,
                        hasChildren: node.hasChildren
                    )
                }
                sessionRow(node.record)
            }

            ForEach(node.children) { child in
                AnyView(
                    SidebarTreeNodeView(
                        node: child,
                        sessionStore: sessionStore,
                        sessionRow: sessionRow
                    )
                )
            }
        }
    }
}

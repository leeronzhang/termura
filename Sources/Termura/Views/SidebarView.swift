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
            footer
        }
        .frame(minWidth: AppConfig.UI.sidebarMinWidth, maxWidth: AppConfig.UI.sidebarMaxWidth)
        .background(themeManager.current.sidebarBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Sessions")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(themeManager.current.sidebarText.opacity(0.6))
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - Session list

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
                ForEach(regularSessions) { session in
                    sessionRow(session)
                }
                .onMove { from, to in
                    sessionStore.reorderSessions(from: from, to: to)
                }
            }
        }
        .listStyle(.sidebar)
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
            if session.isPinned {
                Button("Unpin") { sessionStore.unpinSession(id: session.id) }
            } else {
                Button("Pin") { sessionStore.pinSession(id: session.id) }
            }
            Divider()
            colorLabelMenu(for: session)
            Divider()
            Button("Close Session", role: .destructive) {
                sessionStore.closeSession(id: session.id)
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(themeManager.current.sidebarText.opacity(0.7))
            }
            .buttonStyle(.plain)
            .padding(10)
            Spacer()
        }
        .background(themeManager.current.sidebarBackground)
    }
}

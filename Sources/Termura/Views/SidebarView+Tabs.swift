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
            isActive: sessionStore.activeSessionID == session.id,
            hasUnreadFailure: false,
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
                NotificationCenter.default.post(name: .showExport, object: session.id)
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
        if let store = agentStateStore {
            AgentDashboardView(agentStore: store) { sid in
                sessionStore.activateSession(id: sid)
            }
            .frame(maxWidth: .infinity)
        } else {
            sidebarEmptyState(icon: "cpu", message: "Agent monitoring unavailable")
        }
    }
}

// MARK: - Search Tab

extension SidebarView {
    @ViewBuilder
    var searchContent: some View {
        if let service = searchService {
            SidebarSearchContent(
                searchService: service,
                onSelectSession: { id in sessionStore.activateSession(id: id) }
            )
        } else {
            sidebarEmptyState(icon: "magnifyingglass", message: "Search unavailable")
        }
    }
}

/// Search content following the Agent tab structure: header → divider → content.
struct SidebarSearchContent: View {
    @StateObject private var viewModel: SearchViewModel
    let onSelectSession: (SessionID) -> Void

    init(searchService: SearchService, onSelectSession: @escaping (SessionID) -> Void) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(searchService: searchService))
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            searchField
            resultsList
        }
    }

    private var header: some View {
        HStack {
            Text("Search")
                .panelHeaderStyle()
            Spacer()
            if viewModel.isSearching {
                ProgressView().scaleEffect(0.6)
            }
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var searchField: some View {
        HStack(spacing: AppUI.Spacing.md) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(AppUI.Font.caption)
            TextField("Search\u{2026}", text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(AppUI.Font.body)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    @ViewBuilder
    private var resultsList: some View {
        let allResults: [SearchResult] = viewModel.results.sessions.map { .session($0) }
            + viewModel.results.notes.map { .note($0) }
        if allResults.isEmpty && !viewModel.query.isEmpty && !viewModel.isSearching {
            VStack(spacing: AppUI.Spacing.smMd) {
                Image(systemName: "magnifyingglass")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
                Text("No results")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(allResults) { result in
                        SearchResultRowView(result: result)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if case let .session(s) = result {
                                    onSelectSession(s.id)
                                }
                            }
                    }
                }
                .padding(.horizontal, AppUI.Spacing.sm)
            }
        }
    }
}

// MARK: - Notes Tab

extension SidebarView {
    @ViewBuilder
    var notesContent: some View {
        if let vm = notesViewModel {
            VStack(spacing: 0) {
                notesHeader(vm: vm)
                notesList(vm: vm)
            }
            .task { await vm.loadNotes() }
        } else {
            sidebarEmptyState(icon: "doc.text", message: "Notes unavailable")
        }
    }

    private func notesHeader(vm: NotesViewModel) -> some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            Button { vm.createNote() } label: {
                Image(systemName: "plus")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.md)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private func notesList(vm: NotesViewModel) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(vm.notes) { note in
                    noteRow(note: note, isActive: vm.selectedNoteID == note.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                vm.deleteNote(id: note.id)
                            }
                        }
                }
            }
            .padding(.horizontal, AppUI.Spacing.md)
        }
    }

    private func noteRow(note: NoteRecord, isActive: Bool) -> some View {
        Button {
            onOpenNote?(note.id, note.title)
        } label: {
            HStack {
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .font(isActive ? AppUI.Font.title3Medium : AppUI.Font.title3)
                    .foregroundColor(isActive ? .primary : .secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, AppUI.Spacing.mdLg)
            .padding(.vertical, AppUI.Spacing.smMd)
            .background(
                isActive
                    ? Color.accentColor.opacity(AppUI.Opacity.selected)
                    : Color.clear
            )
            .overlay(
                Rectangle()
                    .stroke(isActive ? Color.accentColor.opacity(AppUI.Opacity.border) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Harness Tab

extension SidebarView {
    @ViewBuilder
    var harnessContent: some View {
        if let appDel = NSApp.delegate as? AppDelegate {
            let repo = appDel.ruleFileRepository
            let projectRoot = activeSessionWorkingDirectory
            SidebarHarnessContent(repository: repo, projectRoot: projectRoot)
        } else {
            sidebarEmptyState(icon: "shield.lefthalf.filled", message: "Harness unavailable")
        }
    }

    var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }) {
            let dir = session.workingDirectory
            if !dir.isEmpty { return dir }
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }
}

/// Harness content following the Agent tab structure: header → divider → content.
struct SidebarHarnessContent: View {
    @StateObject private var viewModel: HarnessViewModel

    init(repository: RuleFileRepository, projectRoot: String) {
        _viewModel = StateObject(wrappedValue: HarnessViewModel(repository: repository, projectRoot: projectRoot))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: false) {
                fileList
                if !viewModel.corruptionResults.isEmpty {
                    corruptionSection
                }
            }
            footer
        }
        .task { await viewModel.loadRuleFiles() }
    }

    private var header: some View {
        HStack {
            Text("Harness")
                .panelHeaderStyle()
            Spacer()
            Button {
                Task { await viewModel.runCorruptionScan() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(AppUI.Font.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selectedFilePath == nil || viewModel.isScanning)
            .help("Scan for issues")
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.mdLg)
    }

    private var fileList: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.ruleFiles) { file in
                Button {
                    Task { await viewModel.selectFile(file.filePath) }
                } label: {
                    HStack(spacing: AppUI.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(AppUI.Font.caption)
                            .foregroundColor(.secondary)
                        Text(file.fileName)
                            .font(AppUI.Font.body)
                            .lineLimit(1)
                        Spacer()
                        Text("v\(file.version)")
                            .font(AppUI.Font.captionMono)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, AppUI.Spacing.mdLg)
                    .padding(.vertical, AppUI.Spacing.smMd)
                    .background(
                        viewModel.selectedFilePath == file.filePath
                            ? Color.accentColor.opacity(AppUI.Opacity.selected)
                            : Color.clear
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppUI.Spacing.sm)
    }

    @ViewBuilder
    private var corruptionSection: some View {
        VStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
            Text("Issues (\(viewModel.corruptionResults.count))")
                .sectionLabelStyle()
                .foregroundColor(.orange)
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.top, AppUI.Spacing.lg)

            ForEach(viewModel.corruptionResults) { result in
                HStack(spacing: AppUI.Spacing.md) {
                    Image(systemName: severityIcon(result.severity))
                        .foregroundColor(severityColor(result.severity))
                        .font(AppUI.Font.caption)
                    Text(result.message)
                        .font(AppUI.Font.label)
                        .lineLimit(2)
                }
                .padding(.horizontal, AppUI.Spacing.lg)
                .padding(.vertical, AppUI.Spacing.xs)
            }
        }
        .padding(.bottom, AppUI.Spacing.md)
    }

    private var footer: some View {
        HStack {
            Text("\(viewModel.ruleFiles.count) files")
                .font(AppUI.Font.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private func severityIcon(_ severity: CorruptionSeverity) -> String {
        switch severity {
        case .error: "xmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private func severityColor(_ severity: CorruptionSeverity) -> Color {
        switch severity {
        case .error: .red
        case .warning: .orange
        case .info: .blue
        }
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

// MARK: - Recursive tree node

struct SidebarTreeNodeView: View {
    let node: SessionTreeNode
    let sessionStore: SessionStore
    let sessionRow: (SessionRecord, (() -> Void)?, Bool) -> AnyView

    @State private var isExpanded = true

    var body: some View {
        if !node.record.isPinned {
            sessionRow(
                node.record,
                node.hasChildren ? {
                    withAnimation(.easeOut(duration: AppUI.Animation.quick)) {
                        isExpanded.toggle()
                    }
                } : nil,
                isExpanded
            )
            .padding(.leading, CGFloat(node.depth) * BranchIndicatorView.indentPerLevel)
            .overlay(alignment: .leading) {
                if node.depth > 0 {
                    BranchIndicatorView(
                        depth: node.depth,
                        branchType: node.record.branchType,
                        hasChildren: node.hasChildren
                    )
                }
            }

            if isExpanded {
                ForEach(node.children) { child in
                    SidebarTreeNodeView(
                        node: child,
                        sessionStore: sessionStore,
                        sessionRow: sessionRow
                    )
                }
            }
        }
    }
}

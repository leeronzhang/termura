import SwiftUI

extension MainView {
    var searchSheet: some View {
        SearchView(
            searchService: dataScope.searchService,
            isPresented: router.showSearch,
            onSelectSession: { id in sessionStore.activateSession(id: id) },
            vectorService: dataScope.vectorSearchService
        )
    }

    var notesSheet: some View {
        NotesSplitView(viewModel: notesViewModel)
            .frame(minWidth: 600, minHeight: 400)
    }

    @ViewBuilder
    var exportSheet: some View {
        // Export is handled by TerminalAreaView which has access to OutputStore chunks.
        // This sheet is a fallback for sessions without an active terminal.
        if let sid = commandRouter.exportSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == sid }) {
            ExportOptionsView(
                session: session,
                chunks: [],
                isPresented: Binding(
                    get: { commandRouter.exportSessionID != nil },
                    set: { if !$0 { commandRouter.exportSessionID = nil } }
                )
            )
        }
    }

    @ViewBuilder
    var harnessSheet: some View {
        let projectRoot = activeSessionWorkingDirectory
        let vm = HarnessViewModel(
            repository: dataScope.ruleFileRepository,
            projectRoot: projectRoot
        )
        HarnessSidebarView(viewModel: vm, isPresented: router.showHarness)
            .frame(minWidth: AppConfig.UI.mainSheetMinWidth, idealHeight: AppConfig.UI.mainSheetIdealHeight)
    }

    /// Working directory of the active session, falling back to home directory.
    var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }),
           let dir = session.workingDirectory {
            return dir
        }
        return AppConfig.Paths.homeDirectory
    }

    @ViewBuilder
    var branchMergeSheet: some View {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }),
           session.parentID != nil {
            BranchMergeSheet(
                branchSession: session,
                chunks: [],
                onMerge: { summary in
                    let msgRepo = dataScope.sessionMessageRepository
                    Task {
                        await sessionStore.mergeBranchSummary(
                            branchID: activeID,
                            summary: summary,
                            messageRepo: msgRepo
                        )
                    }
                    commandRouter.showBranchMerge = false
                },
                onCancel: { commandRouter.showBranchMerge = false }
            )
        }
    }

    var emptyState: some View {
        VStack(spacing: AppUI.Spacing.lg) {
            Image(systemName: "terminal")
                .font(AppUI.Font.hero)
                .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.muted))
            Text("No Active Session")
                .font(AppUI.Font.title1)
                .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.dimmed))
            Text("Press \u{2318}T to create a new session")
                .font(AppUI.Font.label)
                .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.tertiary))
            Button("New Session") {
                sessionStore.createSession(title: "Terminal")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .keyboardShortcut("t", modifiers: .command)
            .padding(.top, AppUI.Spacing.sm)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }
}

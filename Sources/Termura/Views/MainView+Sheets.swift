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
           let session = sessionStore.session(id: sid) {
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
           let dir = sessionStore.session(id: activeID)?.workingDirectory {
            return dir
        }
        return AppConfig.Paths.homeDirectory
    }

    @ViewBuilder
    var branchMergeSheet: some View {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.session(id: activeID),
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
        VStack(spacing: 0) {
            Image(systemName: "terminal")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.muted))
                .padding(.bottom, AppUI.Spacing.lg)
            VStack(spacing: AppUI.Spacing.xs) {
                Text("No Active Session")
                    .font(AppUI.Font.title1)
                    .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.dimmed))
                Text("Press \u{2318}T to create a new session")
                    .font(AppUI.Font.label)
                    .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.tertiary))
            }
            Button {
                sessionStore.createSession(title: "Terminal")
            } label: {
                Text("New Session")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppUI.Spacing.xxxl)
                    .padding(.vertical, AppUI.Spacing.md)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: .command)
            .padding(.top, AppUI.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }

    var notesEmptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "text.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.muted))
                .padding(.bottom, AppUI.Spacing.lg)
            VStack(spacing: AppUI.Spacing.xs) {
                Text("No Note Open")
                    .font(AppUI.Font.title1)
                    .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.dimmed))
                Text("Select a note from the sidebar or create a new one")
                    .font(AppUI.Font.label)
                    .foregroundColor(themeManager.current.foreground.opacity(AppUI.Opacity.tertiary))
            }
            Button {
                commandRouter.pendingCommand = .createNote
            } label: {
                Text("New Note")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, AppUI.Spacing.xxxl)
                    .padding(.vertical, AppUI.Spacing.md)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, AppUI.Spacing.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }
}

import SwiftUI

extension MainView {
    @ViewBuilder
    var exportSheet: some View {
        // Export is handled by TerminalAreaView which has access to OutputStore chunks.
        // This sheet is a fallback for sessions without an active terminal.
        if let sid = exportSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == sid }) {
            ExportOptionsView(
                session: session,
                chunks: [],
                isPresented: $showExport
            )
        }
    }

    @ViewBuilder
    var harnessSheet: some View {
        if let repo = ruleFileRepository {
            let projectRoot = activeSessionWorkingDirectory
            let vm = HarnessViewModel(repository: repo, projectRoot: projectRoot)
            HarnessSidebarView(viewModel: vm, isPresented: $showHarness)
                .frame(minWidth: 300, idealHeight: 500)
        } else {
            VStack(spacing: AppUI.Spacing.lg) {
                Text("Harness Rules")
                    .font(.headline)
                Text("Database not available.")
                    .foregroundColor(.secondary)
                Button("Close") { showHarness = false }
            }
            .frame(minWidth: 300, minHeight: 200)
            .padding(AppUI.Spacing.xxl)
        }
    }

    /// Working directory of the active session, falling back to home directory.
    var activeSessionWorkingDirectory: String {
        if let activeID = sessionStore.activeSessionID,
           let session = sessionStore.sessions.first(where: { $0.id == activeID }) {
            let dir = session.workingDirectory
            if !dir.isEmpty { return dir }
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
                    let msgRepo = sessionMessageRepository
                    Task {
                        await sessionStore.mergeBranchSummary(
                            branchID: activeID,
                            summary: summary,
                            messageRepo: msgRepo
                        )
                    }
                    showBranchMerge = false
                },
                onCancel: { showBranchMerge = false }
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

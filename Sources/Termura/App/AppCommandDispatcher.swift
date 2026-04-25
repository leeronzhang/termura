import Foundation

/// Single entry-point protocol for all menu/keyboard commands dispatched by AppCommands.
/// AppCommands holds `any AppCommandDispatcher` and never penetrates AppDelegate's
/// internal structure (no Law-of-Demeter violations).
@MainActor
protocol AppCommandDispatcher: AnyObject {
    // MARK: - Session commands

    func createNewSession()
    func exportActiveSession()
    func createBranch(type: BranchType)
    func jumpToNextAlert()

    // MARK: - Project commands

    func showProjectPicker()

    // MARK: - CommandRouter forwarding

    func requestSearch()
    func createNote()
    func requestHarness()
    func toggleDualPane()
    func toggleSessionInfo()
    func toggleAgentDashboard()
    func toggleComposer()
    func toggleComposerWithNotes()
    func toggleSidebar()
    func selectSidebarTab(_ tab: SidebarTab)
    func selectSession(at index: Int)
    func cycleContentTab(forward: Bool)
    func focusDualPane(slot: PaneSlot)
    func swapDualPanes()
    func requestBranchMerge()

    // MARK: - Font zoom

    func zoomIn()
    func zoomOut()
    func resetZoom()
}

// MARK: - AppDelegate conformance

extension AppDelegate: AppCommandDispatcher {
    func createNewSession() {
        activeContext?.sessionScope.store.createSession(title: "Terminal")
    }

    func exportActiveSession() {
        guard let ctx = activeContext,
              let id = ctx.sessionScope.store.activeSessionID else { return }
        ctx.commandRouter.requestExport(sessionID: id)
    }

    func createBranch(type: BranchType) {
        guard let store = activeContext?.sessionScope.store,
              let id = store.activeSessionID else { return }
        Task { @MainActor in
            await store.createBranch(from: id, type: type)
        }
    }

    func jumpToNextAlert() {
        guard let ctx = activeContext,
              let targetID = ctx.sessionScope.agentStates.nextAttentionSessionID else { return }
        ctx.sessionScope.store.activateSession(id: targetID)
    }

    func requestSearch() {
        activeContext?.commandRouter.requestSearch()
    }

    func createNote() {
        activeContext?.commandRouter.pendingCommand = .createNote
    }

    func requestHarness() {
        activeContext?.commandRouter.requestHarness()
    }

    func toggleDualPane() {
        activeContext?.commandRouter.toggleDualPane()
    }

    func toggleSessionInfo() {
        activeContext?.commandRouter.toggleSessionInfo()
    }

    func toggleAgentDashboard() {
        activeContext?.commandRouter.toggleAgentDashboard()
    }

    func toggleComposer() {
        activeContext?.commandRouter.toggleComposer()
    }

    func toggleComposerWithNotes() {
        activeContext?.commandRouter.toggleComposerWithNotes()
    }

    func toggleSidebar() {
        activeContext?.commandRouter.toggleSidebar()
    }

    func selectSidebarTab(_ tab: SidebarTab) {
        activeContext?.commandRouter.selectedSidebarTab = tab
    }

    func selectSession(at index: Int) {
        activeContext?.commandRouter.pendingCommand = .selectSession(index: index)
    }

    func cycleContentTab(forward: Bool) {
        activeContext?.commandRouter.pendingCommand = .cycleContentTab(forward: forward)
    }

    func focusDualPane(slot: PaneSlot) {
        activeContext?.commandRouter.focusDualPane(slot)
    }

    func swapDualPanes() {
        activeContext?.commandRouter.pendingCommand = .swapPanes
    }

    func requestBranchMerge() {
        activeContext?.commandRouter.requestBranchMerge()
    }

    func zoomIn() {
        services.fontSettings.zoomIn()
    }

    func zoomOut() {
        services.fontSettings.zoomOut()
    }

    func resetZoom() {
        services.fontSettings.resetZoom()
    }
}

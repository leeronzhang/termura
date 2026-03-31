import AppKit
import SwiftUI

struct AppCommands: Commands {
    // Injected directly from TermuraApp to avoid NSApp.delegate as? AppDelegate,
    // which returns nil when SwiftUI wraps the adaptor in an internal type.
    let appDelegate: AppDelegate

    var body: some Commands {
        sessionCommands
        toolCommands
        viewCommands
        navigationCommands
        alertAndMergeCommands
    }

    // MARK: - Session commands (new item replacement)

    private var sessionCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appDelegate.activeContext?.sessionScope.store.createSession(title: "Terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            // Cmd+W is handled by TabAwareWindow.performClose() to close the active tab.
            // Do NOT add a .keyboardShortcut("w") here -- it conflicts with the system
            // "Close" menu item and causes the window to close instead of the tab.
        }
    }

    // MARK: - Tool commands (after new item)

    private var toolCommands: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Project\u{2026}") {
                appDelegate.showProjectPicker()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Search\u{2026}") {
                appDelegate.activeContext?.commandRouter.requestSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("New Note") {
                appDelegate.activeContext?.commandRouter.pendingCommand = .createNote
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Export Session\u{2026}") {
                guard let id = appDelegate.activeContext?.sessionScope.store.activeSessionID else { return }
                appDelegate.activeContext?.commandRouter.requestExport(sessionID: id)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            newBranchMenu

            Divider()

            Button("Harness Rules\u{2026}") {
                appDelegate.activeContext?.commandRouter.requestHarness()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            splitAndToggleButtons
        }
    }

    @ViewBuilder
    private var splitAndToggleButtons: some View {
        Button("Toggle Dual Pane") {
            appDelegate.activeContext?.commandRouter.toggleDualPane()
        }
        .keyboardShortcut("d", modifiers: .command)

        Divider()

        Button("Toggle Timeline") {
            appDelegate.activeContext?.commandRouter.toggleTimeline()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Button("Toggle Agent Dashboard") {
            appDelegate.activeContext?.commandRouter.toggleAgentDashboard()
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])

        Button("Toggle Composer") {
            appDelegate.activeContext?.commandRouter.toggleComposer()
        }
        .keyboardShortcut("k", modifiers: [.command])

        Button("Toggle Composer with Notes") {
            appDelegate.activeContext?.commandRouter.toggleComposerWithNotes()
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Divider()

        Button("Toggle Sidebar") {
            withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
                appDelegate.activeContext?.commandRouter.toggleSidebar()
            }
        }
        .keyboardShortcut("b", modifiers: .command)
    }

    // MARK: - View commands (zoom, after toolbar)

    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                appDelegate.services.fontSettings.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                appDelegate.services.fontSettings.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                appDelegate.services.fontSettings.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }

    // MARK: - Navigation commands (sidebar tabs, session index, content tab cycling)

    private var navigationCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Divider()
            sidebarTabShortcuts
            Divider()
            sessionIndexShortcuts
            Divider()
            contentTabCycleShortcuts
        }
    }

    /// Cmd+1~5: switch the left sidebar tab (sessions=1, agents=2, harness=3, notes=4, project=5).
    @ViewBuilder
    private var sidebarTabShortcuts: some View {
        ForEach(Array(SidebarTab.allCases.enumerated()), id: \.offset) { index, tab in
            Button(tab.label) {
                appDelegate.activeContext?.commandRouter.selectedSidebarTab = tab
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        }
    }

    /// Ctrl+1~9: activate the session at the given position in the visible session list.
    @ViewBuilder
    private var sessionIndexShortcuts: some View {
        ForEach(0..<9, id: \.self) { index in
            Button("Switch to Session \(index + 1)") {
                appDelegate.activeContext?.commandRouter.pendingCommand = .selectSession(index: index)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
        }
    }

    /// Cmd+Shift+[ / ]: cycle through ContentTab entries backward / forward.
    @ViewBuilder
    private var contentTabCycleShortcuts: some View {
        Button("Previous Tab") {
            appDelegate.activeContext?.commandRouter.pendingCommand = .cycleContentTab(forward: false)
        }
        .keyboardShortcut("[", modifiers: [.command, .shift])

        Button("Next Tab") {
            appDelegate.activeContext?.commandRouter.pendingCommand = .cycleContentTab(forward: true)
        }
        .keyboardShortcut("]", modifiers: [.command, .shift])
    }

    // MARK: - Alert and merge commands

    private var alertAndMergeCommands: some Commands {
        CommandGroup(after: .undoRedo) {
            Button("Jump to Next Alert") {
                guard let ctx = appDelegate.activeContext,
                      let targetID = ctx.sessionScope.agentStates.nextAttentionSessionID else { return }
                ctx.sessionScope.store.activateSession(id: targetID)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Merge Branch Summary\u{2026}") {
                appDelegate.activeContext?.commandRouter.requestBranchMerge()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    @ViewBuilder
    private var newBranchMenu: some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    guard let store = appDelegate.activeContext?.sessionScope.store,
                          let id = store.activeSessionID else { return }
                    Task { @MainActor in
                        await store.createBranch(from: id, type: type)
                    }
                }
            }
        }
    }
}

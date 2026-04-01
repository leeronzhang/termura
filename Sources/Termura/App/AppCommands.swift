import AppKit
import SwiftUI

struct AppCommands: Commands {
    // Injected directly from TermuraApp to avoid NSApp.delegate as? AppDelegate,
    // which returns nil when SwiftUI wraps the adaptor in an internal type.
    let dispatcher: any AppCommandDispatcher

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
                dispatcher.createNewSession()
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
                dispatcher.showProjectPicker()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Search\u{2026}") {
                dispatcher.requestSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("New Note") {
                dispatcher.createNote()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Export Session\u{2026}") {
                dispatcher.exportActiveSession()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            newBranchMenu

            Divider()

            Button("Harness Rules\u{2026}") {
                dispatcher.requestHarness()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            splitAndToggleButtons
        }
    }

    @ViewBuilder
    private var splitAndToggleButtons: some View {
        Button("Toggle Dual Pane") {
            dispatcher.toggleDualPane()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button("Focus Left Pane") {
            dispatcher.focusDualPane(slot: .left)
        }
        .keyboardShortcut(.leftArrow, modifiers: [.control, .shift])

        Button("Focus Right Pane") {
            dispatcher.focusDualPane(slot: .right)
        }
        .keyboardShortcut(.rightArrow, modifiers: [.control, .shift])

        Divider()

        Button("Toggle Inspector") {
            dispatcher.toggleSessionInfo()
        }
        .keyboardShortcut("i", modifiers: [.command, .shift])

        Button("Toggle Agent Dashboard") {
            dispatcher.toggleAgentDashboard()
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])

        Button("Toggle Composer") {
            dispatcher.toggleComposer()
        }
        .keyboardShortcut("k", modifiers: [.command])

        Button("Toggle Composer with Notes") {
            dispatcher.toggleComposerWithNotes()
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])

        Divider()

        Button("Toggle Sidebar") {
            withAnimation(.easeInOut(duration: AppUI.Animation.panel)) {
                dispatcher.toggleSidebar()
            }
        }
        .keyboardShortcut("b", modifiers: .command)
    }

    // MARK: - View commands (zoom, after toolbar)

    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                dispatcher.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                dispatcher.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                dispatcher.resetZoom()
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
                dispatcher.selectSidebarTab(tab)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
        }
    }

    /// Ctrl+1~9: activate the session at the given position in the visible session list.
    @ViewBuilder
    private var sessionIndexShortcuts: some View {
        ForEach(0..<9, id: \.self) { index in
            Button("Switch to Session \(index + 1)") {
                dispatcher.selectSession(at: index)
            }
            .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
        }
    }

    /// Cmd+Shift+[ / ]: cycle through ContentTab entries backward / forward.
    @ViewBuilder
    private var contentTabCycleShortcuts: some View {
        Button("Previous Tab") {
            dispatcher.cycleContentTab(forward: false)
        }
        .keyboardShortcut("[", modifiers: [.command, .shift])

        Button("Next Tab") {
            dispatcher.cycleContentTab(forward: true)
        }
        .keyboardShortcut("]", modifiers: [.command, .shift])
    }

    // MARK: - Alert and merge commands

    private var alertAndMergeCommands: some Commands {
        CommandGroup(after: .undoRedo) {
            Button("Jump to Next Alert") {
                dispatcher.jumpToNextAlert()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Merge Branch Summary\u{2026}") {
                dispatcher.requestBranchMerge()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    @ViewBuilder
    private var newBranchMenu: some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    dispatcher.createBranch(type: type)
                }
            }
        }
    }
}

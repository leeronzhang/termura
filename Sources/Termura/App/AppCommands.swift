import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        sessionCommands
        toolCommands
        viewCommands
        sessionSwitchCommands
        alertAndMergeCommands
    }

    // MARK: - Session commands (new item replacement)

    private var sessionCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appDelegate?.activeContext?.sessionStore.createSession(title: "Terminal")
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
                appDelegate?.showProjectPicker()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Search\u{2026}") {
                appDelegate?.activeContext?.commandRouter.requestSearch()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("New Note") {
                appDelegate?.activeContext?.commandRouter.requestNotes()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Export Session\u{2026}") {
                guard let id = appDelegate?.activeContext?.sessionStore.activeSessionID else { return }
                appDelegate?.activeContext?.commandRouter.requestExport(sessionID: id)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            newBranchMenu

            Divider()

            Button("Harness Rules\u{2026}") {
                appDelegate?.activeContext?.commandRouter.requestHarness()
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            splitAndToggleButtons
        }
    }

    @ViewBuilder
    private var splitAndToggleButtons: some View {
        Button("Split Horizontally") {
            appDelegate?.activeContext?.commandRouter.requestSplitHorizontal()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button("Split Vertically") {
            appDelegate?.activeContext?.commandRouter.requestSplitVertical()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button("Close Split Pane") {
            appDelegate?.activeContext?.commandRouter.requestCloseSplitPane()
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])

        Divider()

        Button("Toggle Timeline") {
            appDelegate?.activeContext?.commandRouter.toggleTimeline()
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])

        Button("Toggle Agent Dashboard") {
            appDelegate?.activeContext?.commandRouter.toggleAgentDashboard()
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])

        Button("Toggle Composer") {
            appDelegate?.activeContext?.commandRouter.toggleComposer()
        }
        .keyboardShortcut("k", modifiers: [.command])
    }

    // MARK: - View commands (zoom, after toolbar)

    private var viewCommands: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Zoom In") {
                (NSApp.delegate as? AppDelegate)?.services.fontSettings.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Zoom Out") {
                (NSApp.delegate as? AppDelegate)?.services.fontSettings.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Actual Size") {
                (NSApp.delegate as? AppDelegate)?.services.fontSettings.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }

    // MARK: - Session switch commands

    private var sessionSwitchCommands: some Commands {
        CommandGroup(after: .undoRedo) {
            Divider()
            SessionSwitchCommands()
        }
    }

    // MARK: - Alert and merge commands

    private var alertAndMergeCommands: some Commands {
        CommandGroup(after: .undoRedo) {
            Button("Jump to Next Alert") {
                guard let ctx = appDelegate?.activeContext,
                      let targetID = ctx.agentStateStore.nextAttentionSessionID else { return }
                ctx.sessionStore.activateSession(id: targetID)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Merge Branch Summary\u{2026}") {
                appDelegate?.activeContext?.commandRouter.requestBranchMerge()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
        }
    }

    @ViewBuilder
    private var newBranchMenu: some View {
        Menu("New Branch") {
            ForEach(BranchType.allCases.filter { $0 != .main }, id: \.self) { type in
                Button(type.rawValue.capitalized) {
                    guard let store = appDelegate?.activeContext?.sessionStore,
                          let id = store.activeSessionID else { return }
                    Task { @MainActor in
                        await store.createBranch(from: id, type: type)
                    }
                }
            }
        }
    }

    private var appDelegate: AppDelegate? {
        NSApp.delegate as? AppDelegate
    }
}

/// Separate view for session switch commands to allow dynamic ForEach.
private struct SessionSwitchCommands: View {
    @State private var sessions: [SessionRecord] = []

    var body: some View {
        ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
            if index < 9 {
                Button(session.title) {
                    (NSApp.delegate as? AppDelegate)?.activeContext?.sessionStore.activateSession(id: session.id)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .onChange(of: sessionCount) { _, _ in
            sessions = (NSApp.delegate as? AppDelegate)?.activeContext?.sessionStore.sessions ?? []
        }
        .onAppear {
            sessions = (NSApp.delegate as? AppDelegate)?.activeContext?.sessionStore.sessions ?? []
        }
    }

    /// Observe the session store's published count to trigger updates.
    private var sessionCount: Int {
        (NSApp.delegate as? AppDelegate)?.activeContext?.sessionStore.sessions.count ?? 0
    }
}

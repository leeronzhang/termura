import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appDelegate?.activeContext?.sessionStore.createSession(title: "Terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Session") {
                guard let store = appDelegate?.activeContext?.sessionStore,
                      let id = store.activeSessionID else { return }
                store.closeSession(id: id)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Open Project\u{2026}") {
                appDelegate?.showProjectPicker()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Search\u{2026}") {
                NotificationCenter.default.post(name: .showSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("New Note") {
                NotificationCenter.default.post(name: .showNotes, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Export Session\u{2026}") {
                guard let id = appDelegate?.activeContext?.sessionStore.activeSessionID else { return }
                NotificationCenter.default.post(name: .showExport, object: id)
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Divider()

            newBranchMenu

            Divider()

            Button("Harness Rules\u{2026}") {
                NotificationCenter.default.post(name: .showHarness, object: nil)
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Divider()

            Button("Split Horizontally") {
                NotificationCenter.default.post(name: .splitHorizontal, object: nil)
            }
            .keyboardShortcut("d", modifiers: .command)

            Button("Split Vertically") {
                NotificationCenter.default.post(name: .splitVertical, object: nil)
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Close Split Pane") {
                NotificationCenter.default.post(name: .closeSplitPane, object: nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])

            Divider()

            Button("Toggle Timeline") {
                NotificationCenter.default.post(name: .toggleTimeline, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Toggle Agent Dashboard") {
                NotificationCenter.default.post(name: .toggleAgentDashboard, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            SessionSwitchCommands()
        }

        CommandGroup(after: .undoRedo) {
            Button("Jump to Next Alert") {
                guard let ctx = appDelegate?.activeContext,
                      let targetID = ctx.agentStateStore.nextAttentionSessionID else { return }
                ctx.sessionStore.activateSession(id: targetID)
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            Button("Merge Branch Summary\u{2026}") {
                NotificationCenter.default.post(name: .showBranchMerge, object: nil)
            }
            .keyboardShortcut("m", modifiers: .command)
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
        .onReceive(
            NotificationCenter.default.publisher(for: .sessionsChanged)
        ) { _ in
            sessions = (NSApp.delegate as? AppDelegate)?.activeContext?.sessionStore.sessions ?? []
        }
    }
}

extension Notification.Name {
    static let sessionsChanged = Notification.Name("com.termura.sessionsChanged")
    static let showSearch = Notification.Name("com.termura.showSearch")
    static let showNotes = Notification.Name("com.termura.showNotes")
    static let showExport = Notification.Name("com.termura.showExport")
    static let showHarness = Notification.Name("com.termura.showHarness")
    static let showBranchMerge = Notification.Name("com.termura.showBranchMerge")
    static let toggleTimeline = Notification.Name("com.termura.toggleTimeline")
    static let toggleAgentDashboard = Notification.Name("com.termura.toggleAgentDashboard")
    static let splitVertical = Notification.Name("com.termura.splitVertical")
    static let splitHorizontal = Notification.Name("com.termura.splitHorizontal")
    static let closeSplitPane = Notification.Name("com.termura.closeSplitPane")
}

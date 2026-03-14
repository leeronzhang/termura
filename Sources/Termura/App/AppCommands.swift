import AppKit
import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                appDelegate?.sessionStore.createSession(title: "Terminal")
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Session") {
                guard let id = appDelegate?.sessionStore.activeSessionID else { return }
                appDelegate?.sessionStore.closeSession(id: id)
            }
            .keyboardShortcut("w", modifiers: .command)
        }

        CommandGroup(after: .newItem) {
            Button("Search\u{2026}") {
                NotificationCenter.default.post(name: .showSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("New Note") {
                NotificationCenter.default.post(name: .showNotes, object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            SessionSwitchCommands()
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
                    (NSApp.delegate as? AppDelegate)?.sessionStore.activateSession(id: session.id)
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .sessionsChanged)
        ) { _ in
            sessions = (NSApp.delegate as? AppDelegate)?.sessionStore.sessions ?? []
        }
    }
}

extension Notification.Name {
    static let sessionsChanged = Notification.Name("com.termura.sessionsChanged")
    static let showSearch = Notification.Name("com.termura.showSearch")
    static let showNotes = Notification.Name("com.termura.showNotes")
}

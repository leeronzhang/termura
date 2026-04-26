import SwiftUI

// MARK: - Note dual-pane view rendering

extension MainView {
    @ViewBuilder
    func noteDualPaneView() -> some View {
        let leftID = tabManager.leftPaneNoteID
        let rightID = tabManager.rightPaneNoteID
        HStack(spacing: 0) {
            noteDualPaneEditor(noteID: leftID, slot: .left, hideButtons: true)

            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(width: 1)

            noteDualPaneEditor(noteID: rightID, slot: .right, hideButtons: false)
        }
        .onAppear {
            commandRouter.focusedNotePaneSlot = .left
            if let leftID { notesViewModel.selectNote(id: leftID) }
        }
    }

    @ViewBuilder
    private func noteDualPaneEditor(noteID: NoteID?, slot: PaneSlot, hideButtons: Bool) -> some View {
        if let noteID {
            let isFocused = commandRouter.focusedNotePaneSlot == slot
            NoteTabContentView(
                noteID: noteID,
                isFocusedPane: isFocused,
                hideToolbarButtons: hideButtons,
                notes: notes,
                onTitleChange: { id, title in syncNoteSplitTitle(noteID: id, title: title) },
                onFocusRequest: {
                    guard commandRouter.focusedNotePaneSlot != slot else { return }
                    commandRouter.focusedNotePaneSlot = slot
                    notesViewModel.selectNote(id: noteID)
                }
            )
            .id(noteID)
            .overlay(alignment: .top) {
                if isFocused {
                    Rectangle().fill(Color.brandGreen).frame(height: 2)
                }
            }
            .background { notePaneSelectionBackground(slot: slot, noteID: noteID) }
        }
    }

    @ViewBuilder
    private func notePaneSelectionBackground(slot: PaneSlot, noteID: NoteID) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                guard commandRouter.focusedNotePaneSlot != slot else { return }
                commandRouter.focusedNotePaneSlot = slot
                notesViewModel.selectNote(id: noteID)
            }
    }

    /// Sync a note title change back into the noteSplit tab so the tab bar stays current.
    private func syncNoteSplitTitle(noteID: NoteID, title: String) {
        guard let idx = tabManager.openTabs.firstIndex(where: { $0.containsNote(noteID) }) else { return }
        let tab = tabManager.openTabs[idx]
        switch tab {
        case .note:
            tabManager.openTabs[idx] = .note(noteID: noteID, title: title)
        case let .noteSplit(left, right, leftTitle, rightTitle):
            let newLeft = left == noteID ? title : leftTitle
            let newRight = right == noteID ? title : rightTitle
            tabManager.openTabs[idx] = .noteSplit(
                left: left, right: right, leftTitle: newLeft, rightTitle: newRight
            )
        default:
            break
        }
        if tabManager.selectedContentTab?.containsNote(noteID) == true {
            tabManager.selectedContentTab = tabManager.openTabs[idx]
        }
    }
}

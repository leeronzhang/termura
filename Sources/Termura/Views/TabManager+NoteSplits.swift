import Foundation

// MARK: - Note Split Management

extension TabManager {
    func toggleNoteSplitTab() {
        guard let current = resolvedSelectedTab else { return }
        if current.isNoteSplit {
            dissolveNoteSplitTab()
        } else if case let .note(noteID, title) = current {
            convertToNoteSplit(leftID: noteID, leftTitle: title)
        }
    }

    func dissolveNoteSplitTab() {
        guard let idx = openTabs.firstIndex(where: { $0 == resolvedSelectedTab }),
              case let .noteSplit(left, right, leftTitle, rightTitle) = openTabs[idx] else { return }
        let focusedSlot = commandRouter?.focusedNotePaneSlot ?? .left
        let keepID = focusedSlot == .left ? left : right
        let keepTitle = focusedSlot == .left ? leftTitle : rightTitle
        let singleTab = ContentTab.note(noteID: keepID, title: keepTitle)
        openTabs[idx] = singleTab
        selectedContentTab = singleTab
        commandRouter?.isNoteDualPaneActive = false
        commandRouter?.focusedNotePaneSlot = .left
        // Re-open the other note as a separate tab so it stays accessible.
        let otherID = focusedSlot == .left ? right : left
        let otherTitle = focusedSlot == .left ? rightTitle : leftTitle
        let otherTab = ContentTab.note(noteID: otherID, title: otherTitle)
        if !openTabs.contains(where: { $0.id == otherTab.id }) {
            openTabs.insert(otherTab, at: idx + 1)
        }
    }

    func swapNotePanes() {
        guard let current = resolvedSelectedTab,
              case let .noteSplit(left, right, leftTitle, rightTitle) = current,
              let idx = openTabs.firstIndex(of: current) else { return }
        let swapped = ContentTab.noteSplit(
            left: right, right: left, leftTitle: rightTitle, rightTitle: leftTitle
        )
        openTabs[idx] = swapped
        selectedContentTab = swapped
        let slot = commandRouter?.focusedNotePaneSlot ?? .left
        commandRouter?.focusedNotePaneSlot = slot == .left ? .right : .left
    }

    func handleFocusNoteDualPane(_ slot: PaneSlot) {
        guard commandRouter?.isNoteDualPaneActive == true else { return }
        guard case let .noteSplit(leftID, rightID, _, _) = resolvedSelectedTab else { return }
        commandRouter?.focusedNotePaneSlot = slot
        let targetID = slot == .left ? leftID : rightID
        notesViewModel?.selectNote(id: targetID)
    }

    // MARK: - Private

    private func convertToNoteSplit(leftID: NoteID, leftTitle: String) {
        let secondary = pickSecondaryNote(excluding: leftID)
        let splitTab = ContentTab.noteSplit(
            left: leftID, right: secondary.id,
            leftTitle: leftTitle, rightTitle: secondary.title
        )
        if let idx = openTabs.firstIndex(where: { $0.containsNote(leftID) }) {
            openTabs[idx] = splitTab
        } else {
            openTabs.append(splitTab)
        }
        // Remove the secondary note's standalone tab to avoid duplicate entries.
        openTabs.removeAll { tab in
            if case let .note(id, _) = tab { return id == secondary.id }
            return false
        }
        selectedContentTab = splitTab
        commandRouter?.isNoteDualPaneActive = true
        commandRouter?.focusedNotePaneSlot = .left
        notesViewModel?.selectNote(id: leftID)
    }

    private func pickSecondaryNote(excluding primaryID: NoteID) -> NoteRecord {
        let all = notesViewModel?.notes ?? []
        if let other = all.first(where: { $0.id != primaryID }) {
            return other
        }
        // Only one note exists — create a new one.
        return notesViewModel?.createNote(title: "Untitled") ?? NoteRecord(title: "Untitled")
    }
}

import Foundation

// MARK: - Split Management

extension TabManager {
    func toggleSplitTab() {
        guard let current = resolvedSelectedTab else { return }
        if current.isSplit {
            dissolveSplitTab()
        } else if case let .terminal(leftID, leftTitle) = current {
            convertToSplitTab(leftID: leftID, leftTitle: leftTitle)
        }
    }

    func dissolveSplitTab() {
        guard let idx = terminalItems.firstIndex(where: { $0 == resolvedSelectedTab }),
              case let .split(left, right, leftTitle, rightTitle) = terminalItems[idx] else { return }
        let leftTab = ContentTab.terminal(sessionID: left, title: leftTitle)
        let rightTab = ContentTab.terminal(sessionID: right, title: rightTitle)
        terminalItems.remove(at: idx)
        terminalItems.insert(rightTab, at: idx)
        terminalItems.insert(leftTab, at: idx)
        selectedContentTab = leftTab
        commandRouter?.isDualPaneActive = false
        commandRouter?.focusedDualPaneID = nil
        sessionStore?.activateSession(id: left)
    }

    func handleFocusDualPane(_ slot: PaneSlot) {
        guard commandRouter?.isDualPaneActive == true, commandRouter?.showComposer == false else { return }
        guard case let .split(leftID, rightID, _, _) = resolvedSelectedTab else { return }
        let targetID = slot == .left ? leftID : rightID
        focusedSlot = slot
        commandRouter?.focusedDualPaneID = targetID
        sessionStore?.activateSession(id: targetID)
    }

    func handleDropSession(_ draggedID: SessionID, onto slot: PaneSlot) {
        guard let splitIdx = terminalItems.firstIndex(where: { $0.isSplit }),
              case let .split(left, right, _, _) = terminalItems[splitIdx] else { return }
        guard let dragged = sessionStore?.session(id: draggedID) else { return }
        let targetID = slot == .left ? left : right
        guard targetID != draggedID else { return }

        if dragged.isEnded {
            Task { @MainActor in
                await sessionStore?.reopenSession(id: draggedID)
                guard sessionStore?.sessions.contains(where: { $0.id == draggedID && !$0.isEnded }) == true else { return }
                guard let currentSplitIdx = terminalItems.firstIndex(where: { $0.isSplit }) else { return }
                let freshTitle = sessionStore?.session(id: draggedID)?.title ?? dragged.title
                applyDropSplit(draggedID: draggedID, title: freshTitle, slot: slot, splitIdx: currentSplitIdx)
            }
        } else {
            applyDropSplit(draggedID: draggedID, title: dragged.title, slot: slot, splitIdx: splitIdx)
        }
    }

    private func convertToSplitTab(leftID: SessionID, leftTitle: String) {
        let secondary = pickSecondarySession(excluding: leftID)
        if secondary.isEnded {
            Task { @MainActor in
                await sessionStore?.reopenSession(id: secondary.id)
                guard let freshSecondary = sessionStore?.session(id: secondary.id) else { return }
                applySplit(leftID: leftID, leftTitle: leftTitle, secondary: freshSecondary)
            }
        } else {
            applySplit(leftID: leftID, leftTitle: leftTitle, secondary: secondary)
        }
    }

    private func applySplit(leftID: SessionID, leftTitle: String, secondary: SessionRecord) {
        let splitTab = ContentTab.split(
            left: leftID,
            right: secondary.id,
            leftTitle: leftTitle,
            rightTitle: secondary.title
        )
        // Remove the secondary session's standalone tab before inserting the split,
        // otherwise two entries contain the same sessionID and sidebar click finds the wrong one.
        terminalItems.removeAll { tab in
            if case let .terminal(sid, _) = tab { return sid == secondary.id }
            return false
        }
        if let idx = terminalItems.firstIndex(where: { $0.containsSession(leftID) }) {
            terminalItems[idx] = splitTab
        } else {
            terminalItems.append(splitTab)
        }
        selectedContentTab = splitTab
        focusedSlot = .left
        commandRouter?.isDualPaneActive = true
        commandRouter?.focusedDualPaneID = leftID
        sessionStore?.ensureEngine(for: secondary.id, shell: nil)
    }

    private func applyDropSplit(draggedID: SessionID, title: String, slot: PaneSlot, splitIdx: Int) {
        guard case let .split(left, right, leftTitle, rightTitle) = terminalItems[splitIdx] else { return }
        let newSplit = ContentTab.split(
            left: slot == .left ? draggedID : left,
            right: slot == .right ? draggedID : right,
            leftTitle: slot == .left ? title : leftTitle,
            rightTitle: slot == .right ? title : rightTitle
        )
        terminalItems[splitIdx] = newSplit
        terminalItems.removeAll { tab in
            if case let .terminal(sid, _) = tab { return sid == draggedID }
            return false
        }
        selectedContentTab = newSplit
        focusedSlot = slot
        commandRouter?.focusedDualPaneID = draggedID
        sessionStore?.ensureEngine(for: draggedID, shell: nil)
        sessionStore?.activateSession(id: draggedID)
    }

    private func pickSecondarySession(excluding leftID: SessionID) -> SessionRecord {
        let all = sessionStore?.sessions ?? []
        let nonEnded = all.filter { !$0.isEnded }
        let visible = visibleSessionIDs()

        let filtered1 = nonEnded.filter { $0.id != leftID && !visible.contains($0.id) }
        if let found = nextSession(after: leftID, in: nonEnded, from: filtered1) { return found }

        let filtered2 = nonEnded.filter { $0.id != leftID }
        if let found = nextSession(after: leftID, in: nonEnded, from: filtered2) { return found }

        let ended = all.filter(\.isEnded)
        if let found = nextSession(after: leftID, in: all, from: ended) { return found }

        return sessionStore?.createSession(title: "Terminal", shell: nil)
            ?? SessionRecord(id: .init(), title: "Terminal", workingDirectory: nil, status: .active)
    }

    private func nextSession(after anchorID: SessionID, in ordered: [SessionRecord], from candidates: [SessionRecord]) -> SessionRecord? {
        guard !candidates.isEmpty else { return nil }
        let anchorIdx = ordered.firstIndex(where: { $0.id == anchorID }) ?? -1
        let afterAnchor = candidates.filter { session in
            (ordered.firstIndex(where: { $0.id == session.id }) ?? 0) > anchorIdx
        }
        return afterAnchor.first ?? candidates.first
    }

    private func visibleSessionIDs() -> Set<SessionID> {
        var ids = Set<SessionID>()
        for tab in terminalItems {
            switch tab {
            case let .terminal(sid, _): ids.insert(sid)
            case let .split(leftID, rightID, _, _): ids.insert(leftID); ids.insert(rightID)
            default: break
            }
        }
        return ids
    }
}

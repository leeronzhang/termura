import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "MainView+SplitActions")

// MARK: - Split tab toggle

extension MainView {
    /// Toggles the current terminal tab between single and split (two-pane) mode.
    func toggleSplitTab() {
        guard let current = resolvedSelectedTab else {
            logger.info("[DIAG] toggleSplitTab: resolvedSelectedTab is nil, returning")
            return
        }
        logger.info("[DIAG] toggleSplitTab: resolvedSelectedTab = \(String(describing: current))")
        if current.isSplit {
            dissolveSplitTab()
        } else if case let .terminal(leftID, leftTitle) = current {
            convertToSplitTab(leftID: leftID, leftTitle: leftTitle)
        } else {
            logger.info("[DIAG] toggleSplitTab: tab is neither split nor terminal, doing nothing")
        }
    }

    /// Dissolves the current split tab into two separate terminal tabs.
    func dissolveSplitTab() {
        guard let idx = terminalItems.firstIndex(where: { $0 == resolvedSelectedTab }),
              case let .split(left, right, leftTitle, rightTitle) = terminalItems[idx] else { return }
        let leftTab = ContentTab.terminal(sessionID: left, title: leftTitle)
        let rightTab = ContentTab.terminal(sessionID: right, title: rightTitle)
        terminalItems.remove(at: idx)
        terminalItems.insert(rightTab, at: idx)
        terminalItems.insert(leftTab, at: idx)
        selectedContentTab = leftTab
        commandRouter.isDualPaneActive = false
        commandRouter.focusedDualPaneID = nil
        sessionStore.activateSession(id: left)
    }

    private func convertToSplitTab(leftID: SessionID, leftTitle: String) {
        let secondary = pickSecondarySession(excluding: leftID)
        logger.info("[DIAG] convertToSplitTab: leftID=\(leftID), secondary=\(secondary.id), isEnded=\(secondary.isEnded)")
        if secondary.isEnded {
            Task { @MainActor in
                await sessionStore.reopenSession(id: secondary.id)
                // Re-fetch after the await: the in-memory record is now updated by reopenSession.
                guard let freshSecondary = sessionStore.session(id: secondary.id) else {
                    logger.error("Session \(secondary.id) missing after reopen — split aborted")
                    return
                }
                applySplit(leftID: leftID, leftTitle: leftTitle, secondary: freshSecondary)
            }
        } else {
            applySplit(leftID: leftID, leftTitle: leftTitle, secondary: secondary)
        }
    }

    private func applySplit(leftID: SessionID, leftTitle: String, secondary: SessionRecord) {
        logger.info("[DIAG] applySplit: leftID=\(leftID), rightID=\(secondary.id)")
        let splitTab = ContentTab.split(
            left: leftID,
            right: secondary.id,
            leftTitle: leftTitle,
            rightTitle: secondary.title
        )
        if let idx = terminalItems.firstIndex(where: { $0.containsSession(leftID) }) {
            terminalItems[idx] = splitTab
        } else {
            terminalItems.append(splitTab)
        }
        selectedContentTab = splitTab
        focusedSlot = .left
        commandRouter.isDualPaneActive = true
        commandRouter.focusedDualPaneID = leftID
        sessionStore.ensureEngine(for: secondary.id)
    }
}

// MARK: - Keyboard focus switch

extension MainView {
    /// Focus a specific pane in dual-pane mode via keyboard shortcut (Ctrl+left/right arrow).
    /// Mirrors the composer invariant from the mouse monitor: focus must not shift
    /// while the composer is open in the currently active pane.
    func handleFocusDualPane(_ slot: PaneSlot) {
        guard commandRouter.isDualPaneActive, !commandRouter.showComposer else { return }
        guard case let .split(leftID, rightID, _, _) = resolvedSelectedTab else { return }
        let targetID = slot == .left ? leftID : rightID
        focusedSlot = slot
        commandRouter.focusedDualPaneID = targetID
        sessionStore.activateSession(id: targetID)
    }
}

// MARK: - Secondary session selection

extension MainView {
    /// Picks the secondary pane session when entering split mode.
    /// Priority: (1) next non-ended not already visible, (2) next non-ended,
    /// (3) next ended session (will be reopened), (4) create new session.
    func pickSecondarySession(excluding leftID: SessionID) -> SessionRecord {
        let all = sessionStore.sessions
        let nonEnded = all.filter { !$0.isEnded }
        let visible = visibleSessionIDs()

        if let found = nextSession(after: leftID, in: nonEnded,
                                   from: nonEnded.filter { $0.id != leftID && !visible.contains($0.id) }) {
            return found
        }
        if let found = nextSession(after: leftID, in: nonEnded,
                                   from: nonEnded.filter { $0.id != leftID }) {
            return found
        }
        let ended = all.filter { $0.isEnded }
        if let found = nextSession(after: leftID, in: all, from: ended) {
            return found
        }
        return sessionStore.createSession(title: "Terminal")
    }

    /// Returns the session immediately after `anchorID` in `ordered`, restricted to `candidates`.
    /// Wraps around to the beginning if the anchor is at the end.
    private func nextSession(
        after anchorID: SessionID,
        in ordered: [SessionRecord],
        from candidates: [SessionRecord]
    ) -> SessionRecord? {
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

// MARK: - Drag-and-drop pane replacement

extension MainView {
    /// Replaces the session in `slot` with `draggedID` when a session is dragged onto a split pane.
    /// The displaced session remains in the sidebar list without a tab.
    /// If `draggedID` had a standalone terminal tab, that tab is removed.
    /// Ended sessions are reopened automatically; UI is only updated after a successful reopen.
    func handleDropSession(_ draggedID: SessionID, onto slot: PaneSlot) {
        guard let splitIdx = terminalItems.firstIndex(where: { $0.isSplit }),
              case let .split(left, right, _, _) = terminalItems[splitIdx] else { return }
        guard let dragged = sessionStore.session(id: draggedID) else { return }
        let targetID = slot == .left ? left : right
        guard targetID != draggedID else { return }

        if dragged.isEnded {
            Task { @MainActor in
                await sessionStore.reopenSession(id: draggedID)
                // Re-check after the await: reopenSession may have failed and the session
                // may still be ended in memory. Only mutate UI on confirmed success.
                guard sessionStore.sessions.contains(where: { $0.id == draggedID && !$0.isEnded }) else {
                    logger.error("Session \(draggedID) could not be reopened for drop onto slot \(String(describing: slot))")
                    return
                }
                // Re-locate the split tab in case the user made changes during the await.
                guard let currentSplitIdx = terminalItems.firstIndex(where: { $0.isSplit }) else { return }
                let freshTitle = sessionStore.session(id: draggedID)?.title ?? dragged.title
                applyDropSplit(draggedID: draggedID, title: freshTitle, slot: slot, splitIdx: currentSplitIdx)
            }
        } else {
            applyDropSplit(draggedID: draggedID, title: dragged.title, slot: slot, splitIdx: splitIdx)
        }
    }

    /// Applies the drag-and-drop replacement in place. Reads current split state from
    /// `terminalItems[splitIdx]` so that post-await callers always use fresh data.
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
        commandRouter.focusedDualPaneID = draggedID
        sessionStore.ensureEngine(for: draggedID)
        sessionStore.activateSession(id: draggedID)
    }
}

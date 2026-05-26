import SwiftUI

// MARK: - Dual-pane view rendering

extension MainView {
    @ViewBuilder
    func dualPaneView() -> some View {
        HStack(spacing: 0) {
            dualPaneTerminal(sessionID: leftPaneSessionID, slot: .left, hideButtons: true)

            Rectangle()
                .fill(themeManager.current.sidebarText.opacity(AppUI.Opacity.softBorder))
                .frame(width: 1)

            dualPaneTerminal(sessionID: rightPaneSessionID, slot: .right, hideButtons: false)

            dualPaneMetadata(focusedID: focusedPaneSessionID)
        }
        .onAppear {
            // Restore the user's last focused pane for this split tab so leaving
            // and re-entering does not snap focus back to the left side.
            guard let tab = resolvedSelectedTab, tab.isSplit else { return }
            let slot = tabManager.restoredFocusedSlot(for: tab)
            tabManager.focusedSlot = slot
            commandRouter.focusedDualPaneID = slot == .left ? leftPaneSessionID : rightPaneSessionID
        }
    }

    @ViewBuilder
    func dualPaneTerminal(sessionID: SessionID?, slot: PaneSlot, hideButtons: Bool) -> some View {
        if let sessionID {
            if let engine = engineStore.engine(for: sessionID) {
                let isFocused = focusedSlot == slot
                let state = viewStateManager.viewState(for: sessionID, engine: engine)
                TerminalAreaView(
                    engine: engine,
                    sessionID: sessionID,
                    forceHideMetadata: true,
                    isFocusedPane: isFocused,
                    hideToolbarButtons: hideButtons,
                    onDropFocus: { tabManager.focusPane(holding: sessionID) },
                    state: state
                )
                .id(sessionID)
                .overlay(alignment: .top) {
                    if isFocused {
                        Rectangle().fill(Color.brandGreen).frame(height: 2)
                    }
                }
                .overlay {
                    if dropTargetSlot == slot {
                        RoundedRectangle(cornerRadius: AppUI.Radius.sm)
                            .stroke(Color.brandGreen.opacity(AppUI.Opacity.border), lineWidth: 2)
                            .allowsHitTesting(false)
                    }
                }
                .background { paneSelectionBackground(sessionID: sessionID) }
                .dropDestination(for: String.self) { items, _ in
                    guard let str = items.first,
                          let uuid = UUID(uuidString: str) else { return false }
                    let draggedID = SessionID(rawValue: uuid)
                    let isIntraSplitDrag = resolvedSelectedTab?.containsSession(draggedID) ?? false
                    if isIntraSplitDrag {
                        swapPanes()
                    } else {
                        handleDropSession(draggedID, onto: slot)
                    }
                    return true
                } isTargeted: { isTargeted in
                    dropTargetSlot = isTargeted ? slot : nil
                }
            } else {
                // Engine not yet created — the focused session gets its engine during
                // loadPersistedSessions; all others are created on demand. TerminalEngineStore
                // is @Observable, so the view re-renders once the engine is inserted.
                Color.clear
                    .task(id: sessionID) {
                        sessionStore.ensureEngine(for: sessionID, shell: nil)
                    }
            }
        }
    }

    @ViewBuilder
    private func paneSelectionBackground(sessionID: SessionID) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Focus the clicked pane. focusPane(holding:) no-ops while the composer is
                // open on a different pane — changing focus would move the composer and give
                // the terminal NSView first responder, sending subsequent Cmd+V to the PTY.
                tabManager.focusPane(holding: sessionID)
            }
    }

    @ViewBuilder
    func dualPaneMetadata(focusedID: SessionID?) -> some View {
        if let focusedID,
           commandRouter.showDualPaneMetadata,
           let engine = engineStore.engine(for: focusedID) {
            let state = viewStateManager.viewState(for: focusedID, engine: engine)
            ResizableDivider(
                width: .constant(AppConfig.UI.metadataPanelWidth),
                minWidth: AppConfig.UI.metadataPanelMinWidth,
                maxWidth: AppConfig.UI.metadataPanelMaxWidth,
                dragFactor: -1.0
            )
            SessionMetadataBarView(
                metadata: state.viewModel.currentMetadata,
                sessionTitle: sessionScope.store.sessionTitles[focusedID] ?? "Session",
                timeline: state.timeline,
                onSelectChunkID: { chunkID in
                    guard let turn = state.timeline.turns.first(where: { $0.chunkID == chunkID }),
                          let line = turn.startLine else { return }
                    Task { await engine.scrollToLine(line) }
                }
            )
            .frame(width: AppConfig.UI.metadataPanelWidth)
        }
    }
}

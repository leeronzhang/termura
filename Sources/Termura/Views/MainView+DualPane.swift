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
            tabManager.focusedSlot = .left
            commandRouter.focusedDualPaneID = leftPaneSessionID
        }
    }

    @ViewBuilder
    func dualPaneTerminal(sessionID: SessionID?, slot: PaneSlot, hideButtons: Bool) -> some View {
        if let sessionID, let engine = engineStore.engine(for: sessionID) {
            let isFocused = focusedSlot == slot
            let state = viewStateManager.viewState(for: sessionID, engine: engine)
            TerminalAreaView(
                engine: engine,
                sessionID: sessionID,
                forceHideMetadata: true,
                isFocusedPane: isFocused,
                hideToolbarButtons: hideButtons,
                state: state
            )
            .id(sessionID)
            .overlay(alignment: .top) {
                if isFocused {
                    Rectangle().fill(Color.accentColor).frame(height: 2)
                }
            }
            .overlay {
                if dropTargetSlot == slot {
                    RoundedRectangle(cornerRadius: AppUI.Radius.sm)
                        .stroke(Color.accentColor.opacity(AppUI.Opacity.border), lineWidth: 2)
                        .allowsHitTesting(false)
                }
            }
            .background { paneSelectionBackground(slot: slot, sessionID: sessionID) }
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first,
                      let uuid = UUID(uuidString: str) else { return false }
                handleDropSession(SessionID(rawValue: uuid), onto: slot)
                return true
            } isTargeted: { isTargeted in
                dropTargetSlot = isTargeted ? slot : nil
            }
        }
    }

    @ViewBuilder
    private func paneSelectionBackground(slot: PaneSlot, sessionID: SessionID) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                // Don't shift pane focus while the composer is open in the currently focused
                // pane — changing focus would move the composer and give the terminal NSView
                // first responder, causing subsequent Cmd+V paste to land in the PTY.
                if commandRouter.showComposer && focusedSlot != slot { return }
                tabManager.focusedSlot = slot
                commandRouter.focusedDualPaneID = sessionID
                sessionStore.activateSession(id: sessionID)
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

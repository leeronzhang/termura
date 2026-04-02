import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalAreaView")

/// Opaque token returned by `NSEvent.addLocalMonitorForEvents`.
/// Apple's API returns `Any?` — this typealias improves intent clarity.
typealias NSEventMonitorToken = Any

/// Composes the terminal display, chunked output overlay, metadata panel, and editor input.
/// Session lifetime is tied to the session via `.id(sessionID)` in the parent.
struct TerminalAreaView: View {
    let engine: any TerminalEngine
    let sessionID: SessionID
    /// When true (split pane mode), hides side panels and toolbar to save space.
    var isCompact: Bool = false
    /// When true, metadata panel is managed externally (dual-pane mode).
    var forceHideMetadata: Bool = false
    /// When false (non-focused pane in dual mode), composer and backdrop are suppressed.
    var isFocusedPane: Bool = true
    /// When true, toolbar action buttons are hidden (shared toolbar in dual-pane mode).
    var hideToolbarButtons: Bool = false

    @Environment(\.sessionScope) var sessionScope
    @Environment(\.commandRouter) var commandRouter
    @Environment(\.themeManager) var themeManager
    @Environment(\.fontSettings) var fontSettings
    @Environment(\.notesViewModel) var notesViewModel
    /// Per-session state container — owned by `SessionViewStateManager`.
    /// `@Bindable` enables `$state.viewModel.pendingRiskAlert` binding syntax
    /// while `@Observable` on SessionViewState handles automatic re-renders.
    @Bindable var state: SessionViewState

    // MARK: - Convenience accessors

    var showComposer: Bool { commandRouter.showComposer }

    var outputStore: OutputStore { state.outputStore }
    var modeController: InputModeController { state.modeController }
    var viewModel: TerminalViewModel { state.viewModel }
    var editorViewModel: EditorViewModel { state.editorViewModel }
    var timeline: SessionTimeline { state.timeline }

    /// Consolidated view-local UI state to reduce @State count.
    @State var localUI = LocalUIState()
    /// Token returned by NSEvent.addLocalMonitorForEvents; retained for removal on disappear.
    /// Apple's API returns `Any?` — no stronger type available.
    @State var keyEventMonitor: NSEventMonitorToken?
    @State var mouseEventMonitor: NSEventMonitorToken?

    /// Shared handle — lives in SessionViewState so MainView can access it for the Composer.
    var editorHandle: EditorViewHandle { state.editorHandle }

    // MARK: - Body

    var body: some View {
        mainLayout
            .overlay(alignment: .bottom) { notesOverlay }
            .animation(.easeInOut(duration: 0.25), value: notesViewModel.toastMessage != nil)
            .overlay(alignment: .bottom) { riskAlertOverlay }
            .animation(.easeInOut(duration: 0.25), value: state.viewModel.pendingRiskAlert != nil)
            .overlay(alignment: .bottom) { contextWindowOverlay }
            .animation(.easeInOut(duration: 0.25), value: state.viewModel.contextWindowAlert != nil)
            .onAppear { onViewAppear() }
            .onDisappear { removeKeyRouter() }
            .modifier(TerminalAreaSheets(
                showExportSheet: $localUI.showExportSheet,
                showContextSheet: $localUI.showContextSheet,
                sessionID: sessionID,
                sessionStore: sessionScope.store,
                outputStore: outputStore,
                viewModel: viewModel,
                projectRoot: sessionScope.store.projectRoot ?? ""
            ))
            .onChange(of: outputStore.chunks.count) { old, new in
                guard new > old, let latest = outputStore.chunks.last else { return }
                let startLine = engine.supportsScrollbackNavigation ? engine.currentScrollLine() : nil
                timeline.append(latest, startLine: startLine)
            }
            .onAppear { checkContextFileExists() }
            .onChange(of: sessionScope.store.sessions.count) { old, new in
                registerNewBranchMarkers(oldCount: old, newCount: new)
            }
    }

    // MARK: - Bottom overlays

    /// Notes silent-capture toast — only shown in the focused pane in dual-pane mode.
    @ViewBuilder
    private var notesOverlay: some View {
        if let message = notesViewModel.toastMessage,
           !commandRouter.isDualPaneActive || isFocusedPane {
            Button {
                notesViewModel.toastMessage = nil
                commandRouter.pendingCommand = .openLastSilentNote
            } label: {
                Text(message)
                    .font(AppUI.Font.bodyMedium)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, AppUI.Spacing.xxl)
                    .padding(.vertical, AppUI.Spacing.md)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppUI.Spacing.md))
            }
            .buttonStyle(.plain)
            .padding(.bottom, AppUI.Spacing.xxl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var riskAlertOverlay: some View {
        if let risk = state.viewModel.pendingRiskAlert {
            RiskAlertBannerView(
                alert: risk,
                onStopAgent: {
                    state.viewModel.dismissRiskAlert()
                    let eng = engine
                    Task { await eng.send("\u{03}") }
                },
                onAllow: { state.viewModel.dismissRiskAlert() }
            )
        }
    }

    @ViewBuilder
    private var contextWindowOverlay: some View {
        if let alert = state.viewModel.contextWindowAlert {
            ContextWindowAlertView(alert: alert) {
                state.viewModel.contextWindowAlert = nil
            }
        }
    }

    private func registerNewBranchMarkers(oldCount: Int, newCount: Int) {
        guard newCount > oldCount else { return }
        let sid = sessionID
        let tl = timeline
        let added = sessionScope.store.sessions.suffix(newCount - oldCount)
        for session in added {
            guard session.parentID == sid else { continue }
            let marker = BranchPointMarker(
                branchID: session.id,
                branchType: session.branchType,
                createdAt: session.createdAt
            )
            tl.addBranchMarker(at: tl.turns.indices.last ?? 0, marker: marker)
        }
    }

    // MARK: - Extracted layout

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                terminalAndOutputArea

                if !isCompact && state.showMetadata && !forceHideMetadata {
                    ResizableDivider(
                        width: $localUI.metadataPanelWidth,
                        minWidth: AppConfig.UI.metadataPanelMinWidth,
                        maxWidth: AppConfig.UI.metadataPanelMaxWidth,
                        dragFactor: -1.0
                    )
                    SessionMetadataBarView(
                        metadata: viewModel.currentMetadata,
                        sessionTitle: sessionScope.store.sessionTitles[sessionID] ?? "Session",
                        timeline: timeline,
                        onSelectChunkID: scrollToChunk
                    )
                    .frame(width: localUI.metadataPanelWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(themeManager.current.background)
        }
        // Composer overlay is rendered inside terminalAndOutputArea as a bottom sheet.
    }

    // MARK: - Lifecycle

    private func onViewAppear() {
        installKeyRouter()
        checkContextFileExists()
        editorViewModel.onCommandSubmit = { [weak viewModel] cmd in
            viewModel?.detectAgentFromCommand(cmd)
        }
        // Wire at session-view level: stable across Composer onAppear/onDisappear cycles.
        let router = commandRouter
        editorViewModel.onSubmit = { [weak router] in router?.dismissComposer() }
        setupAgentResumeIfNeeded()
        wireTerminalContextActions()
    }

    /// Connects the terminal view's right-click context actions to the CommandRouter and NotesViewModel.
    private func wireTerminalContextActions() {
        guard let ghosttyView = engine.terminalNSView as? GhosttyTerminalView else { return }
        let router = commandRouter
        let notes = notesViewModel
        let eng = engine
        ghosttyView.contextMenuActions = GhosttyTerminalView.ContextMenuActions(
            onQuoteInComposer: { [weak router] text in
                router?.prefillComposer(text: text)
            },
            onAskAboutThis: { [weak router] text in
                router?.prefillComposer(text: text)
            },
            onSendToNotes: { [weak notes] text in
                let title = String(text.prefix(40)).trimmingCharacters(in: .whitespacesAndNewlines)
                notes?.silentlyCreateNote(title: title, body: text)
                notes?.showToast("Saved to Notes")
            },
            onClearTerminal: { [weak eng] in
                guard let eng else { return }
                Task { await eng.send("clear\r") }
            }
        )
    }

    /// Registers a one-shot callback on the TerminalViewModel to pre-fill the Composer
    /// with the previous agent's resume command when the first shell prompt is detected.
    /// Only fires for restored sessions with a known agent type.
    /// Skipped when ContextInjectionService is available — PTY injection already sends
    /// the resume command directly to the terminal, making Composer pre-fill redundant.
    private func setupAgentResumeIfNeeded() {
        // PTY-level injection handles resume; Composer pre-fill is the fallback path only.
        guard !viewModel.sessionServices.hasContextInjection else { return }
        let store = sessionScope.store
        guard store.isRestoredSession(id: sessionID) else { return }
        guard let session = store.session(id: sessionID) else { return }
        let agentType = session.agentType
        guard agentType != .unknown, !agentType.resumeCommand.isEmpty else { return }
        let router = commandRouter
        let vm = viewModel
        vm.onShellPromptReadyForResume = {
            router.pendingCommand = .resumeAgent(agentType)
        }
    }

    /// Scrolls the terminal to the position where the chunk with the given ID starts.
    /// No-op if the turn has no recorded startLine (e.g., captured before this feature existed).
    func scrollToChunk(_ chunkID: UUID) {
        guard let turn = timeline.turns.first(where: { $0.chunkID == chunkID }),
              let line = turn.startLine else { return }
        Task { await engine.scrollToLine(line) }
    }

    private func checkContextFileExists() {
        guard let root = sessionScope.store.projectRoot, !root.isEmpty else {
            localUI.contextFileExists = false
            return
        }
        let path = URL(fileURLWithPath: root)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appendingPathComponent(AppConfig.SessionHandoff.contextFileName).path
        // Lifecycle: one-shot cosmetic check. fileExists is a synchronous stat(2) syscall
        // that can block on network mounts or under I/O pressure — must not run on MainActor.
        Task.detached { [path] in
            let exists = FileManager.default.fileExists(atPath: path)
            await MainActor.run { localUI.contextFileExists = exists }
        }
    }
}

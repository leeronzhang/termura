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
            .overlay(alignment: .bottom) {
                if let message = notesViewModel.toastMessage {
                    Text(message)
                        .font(AppUI.Font.bodyMedium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppUI.Spacing.xxl)
                        .padding(.vertical, AppUI.Spacing.md)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppUI.Spacing.md))
                        .padding(.bottom, AppUI.Spacing.xxl)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: notesViewModel.toastMessage != nil)
            .overlay(alignment: .bottom) {
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
            .animation(.easeInOut(duration: 0.25), value: state.viewModel.pendingRiskAlert != nil)
            .onAppear { onViewAppear() }
            .onDisappear { removeKeyRouter() }
            .modifier(TerminalAreaSheets(
                contextWindowAlert: $state.viewModel.contextWindowAlert,
                showExportSheet: $localUI.showExportSheet,
                showContextSheet: $localUI.showContextSheet,
                sessionID: sessionID,
                sessionStore: sessionScope.store,
                outputStore: outputStore,
                viewModel: viewModel
            ))
            .onChange(of: outputStore.chunks.count) { old, new in
                guard new > old, let latest = outputStore.chunks.last else { return }
                timeline.append(latest, startLine: engine.currentScrollLine())
            }
            .onChange(of: viewModel.currentMetadata.workingDirectory) { _, _ in
                checkContextFileExists()
            }
            .onChange(of: sessionScope.store.sessions.count) { old, new in
                guard new > old else { return }
                let sid = sessionID
                let tl = timeline
                let added = sessionScope.store.sessions.suffix(new - old)
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
    /// Only wires when the engine exposes a TermuraTerminalView; no-ops for mocks.
    private func wireTerminalContextActions() {
        guard let tv = engine.terminalNSView as? TermuraTerminalView else { return }
        let router = commandRouter
        tv.onContextAction = { text in
            router.prefillComposer(text: text)
        }
        let notes = notesViewModel
        let store = sessionScope.store
        let sid = sessionID
        tv.onSendToNotes = { text in
            let title = store.session(id: sid)?.title ?? "Terminal"
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = "```\n\(trimmed)\n```"
            notes.silentlyCreateNote(title: title, body: body)
            notes.showToast("Saved to Notes")
        }
    }

    /// Registers a one-shot callback on the TerminalViewModel to pre-fill the Composer
    /// with the previous agent's launch command when the first shell prompt is detected.
    /// Only fires for restored sessions with a known agent type.
    private func setupAgentResumeIfNeeded() {
        let store = sessionScope.store
        guard store.isRestoredSession(id: sessionID) else { return }
        guard let session = store.session(id: sessionID) else { return }
        let agentType = session.agentType
        guard agentType != .unknown, !agentType.defaultLaunchCommand.isEmpty else { return }
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
        let dir = viewModel.currentMetadata.workingDirectory
        guard !dir.isEmpty else {
            localUI.contextFileExists = false
            return
        }
        let path = URL(fileURLWithPath: dir)
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

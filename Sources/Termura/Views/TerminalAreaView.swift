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
    @State private var keyEventMonitor: NSEventMonitorToken?
    @State private var mouseEventMonitor: NSEventMonitorToken?

    /// Shared handle — lives in SessionViewState so MainView can access it for the Composer.
    var editorHandle: EditorViewHandle { state.editorHandle }

    // MARK: - Body

    var body: some View {
        mainLayout
            .onAppear { onViewAppear() }
            .onDisappear { removeKeyRouter() }
            .modifier(TerminalAreaSheets(
                riskAlert: $state.viewModel.pendingRiskAlert,
                contextWindowAlert: $state.viewModel.contextWindowAlert,
                showExportSheet: $localUI.showExportSheet,
                showContextSheet: $localUI.showContextSheet,
                engine: engine,
                sessionID: sessionID,
                sessionStore: sessionScope.store,
                outputStore: outputStore,
                viewModel: viewModel
            ))
            .onChange(of: outputStore.chunks.count) { old, new in
                guard new > old, let latest = outputStore.chunks.last else { return }
                timeline.append(latest)
            }
            .onChange(of: viewModel.currentMetadata.workingDirectory) { _, _ in
                checkContextFileExists()
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
                        timeline: timeline,
                        onSelectChunkID: { _ in }
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

    /// Connects the terminal view's right-click context actions to the CommandRouter.
    /// Only wires when the engine exposes a TermuraTerminalView; no-ops for mocks.
    private func wireTerminalContextActions() {
        guard let tv = engine.terminalNSView as? TermuraTerminalView else { return }
        let router = commandRouter
        tv.onContextAction = { text in
            router.prefillComposer(text: text)
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

    // MARK: - Key routing

    /// Ensures focus always lands on EditorTextView when a key is pressed.
    /// Ctrl+letter and Escape are handled by EditorTextView.keyDown → PTY directly.
    ///
    /// `NSEvent.addLocalMonitorForEvents` monitors the *current thread's* run loop.
    /// Since we install from the main thread, the callback always fires on main.
    /// `dispatchPrecondition` asserts this at runtime in DEBUG builds.
    private func installKeyRouter() {
        let modeCtrl = modeController
        let termEngine = engine
        let router = commandRouter
        let sid = sessionID
        let handle = editorHandle
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            dispatchPrecondition(condition: .onQueue(.main))

            // In dual-pane mode, only the focused pane handles key events.
            if router.isDualPaneActive, router.focusedDualPaneID != sid {
                return event
            }

            guard let window = NSApp.keyWindow else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Intercept Cmd+K directly to toggle composer.
            if flags == .command, event.charactersIgnoringModifiers == "k" {
                router.toggleComposer()
                return nil
            }
            // Escape closes composer (without clearing text).
            if router.showComposer, event.keyCode == 53 {
                router.dismissComposer()
                return nil
            }
            // Let other Cmd-key shortcuts pass through to the menu system.
            if flags.contains(.command) { return event }
            // When Composer is open, let all events flow to the Composer's views.
            // Defense-in-depth: if the user clicked the notes list or any non-editor
            // view and EditorTextView lost first responder, reclaim it on Cmd+V so
            // paste always lands in the composer editor and never in the terminal PTY.
            if router.showComposer {
                if flags == .command,
                   event.charactersIgnoringModifiers == "v",
                   let textView = handle.textView,
                   window.firstResponder !== textView {
                    window.makeFirstResponder(textView)
                }
                return event
            }
            // In passthrough mode route keys to the terminal.
            if modeCtrl.mode == .passthrough {
                let termView = termEngine.terminalNSView
                if window.firstResponder !== termView {
                    window.makeFirstResponder(termView)
                }
                termView.keyDown(with: event)
                return nil
            }
            return event
        }
        // Mouse monitor: dual-pane focus tracking only.
        // Composer backdrop dismissal is handled by AppKitClickableOverlay (TerminalAreaView+Subviews).
        //
        // Invariant: while showComposer == true, focusedDualPaneID must not change.
        // Shifting focus to another pane would (a) visually move the composer to that
        // pane and (b) give the terminal NSView first responder, causing Cmd+V paste
        // to land in the PTY instead of the composer editor.
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if router.isDualPaneActive {
                let termView = termEngine.terminalNSView
                let loc = termView.convert(event.locationInWindow, from: nil)
                if termView.bounds.contains(loc) {
                    // Don't shift pane focus or give the terminal first responder while
                    // the composer is open in the currently focused pane.
                    if router.showComposer && router.focusedDualPaneID != sid {
                        return event
                    }
                    router.focusedDualPaneID = sid
                    if let window = termView.window, window.firstResponder !== termView {
                        window.makeFirstResponder(termView)
                    }
                }
            }
            return event
        }
    }

    private func removeKeyRouter() {
        editorViewModel.onSubmit = nil
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
        if let monitor = mouseEventMonitor {
            NSEvent.removeMonitor(monitor)
            mouseEventMonitor = nil
        }
    }
}

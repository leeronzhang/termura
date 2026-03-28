import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalAreaView")

/// Opaque token returned by `NSEvent.addLocalMonitorForEvents`.
/// Apple's API returns `Any?` — this typealias improves intent clarity.
typealias NSEventMonitorToken = Any

/// Composes the terminal display, chunked output overlay, metadata panel, and editor input.
/// All @StateObject lifetimes are tied to the session via `.id(sessionID)` in the parent.
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
    /// Per-session state container — owned by `SessionViewStateManager`,
    /// received here as `@ObservedObject` to avoid the fragile `@StateObject`-in-init pattern.
    @ObservedObject var state: SessionViewState

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

                if !isCompact && localUI.showMetadata && !forceHideMetadata {
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
            commandRouter.dismissComposer()
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
        // Lifecycle: one-shot file check — result is cosmetic UI state, no cleanup needed.
        // fileExists is a fast syscall; running on MainActor avoids the @State capture risk
        // that arises when Task.detached + MainActor.run is used with value-type wrappers.
        Task { @MainActor in
            localUI.contextFileExists = FileManager.default.fileExists(atPath: path)
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
            if router.showComposer { return event }
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
        // Composer backdrop dismissal is handled by SwiftUI tap gesture (TerminalAreaView+Subviews).
        mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if router.isDualPaneActive {
                let termView = termEngine.terminalNSView
                let loc = termView.convert(event.locationInWindow, from: nil)
                if termView.bounds.contains(loc) {
                    router.focusedDualPaneID = sid
                }
            }
            return event
        }
    }

    private func removeKeyRouter() {
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

// MARK: - Local UI State

/// Groups view-local @State booleans/doubles that only affect TerminalAreaView layout.
struct LocalUIState {
    var showMetadata = true
    var showExportSheet = false
    var showContextSheet = false
    var contextFileExists = false
    var metadataPanelWidth: Double = AppConfig.UI.metadataPanelWidth
}

// MARK: - Sheet modifiers

private struct TerminalAreaSheets: ViewModifier {
    @Binding var riskAlert: RiskAlert?
    @Binding var contextWindowAlert: ContextWindowAlert?
    @Binding var showExportSheet: Bool
    @Binding var showContextSheet: Bool
    let engine: any TerminalEngine
    let sessionID: SessionID
    let sessionStore: SessionStore
    let outputStore: OutputStore
    let viewModel: TerminalViewModel

    func body(content: Content) -> some View {
        let eng = engine
        content
            .sheet(item: $riskAlert) { risk in
                InterventionAlertView(
                    alert: risk,
                    onProceed: { riskAlert = nil },
                    onCancel: {
                        riskAlert = nil
                        Task { await eng.send("\u{03}") }
                    }
                )
            }
            .sheet(item: $contextWindowAlert) { alert in
                ContextWindowAlertView(alert: alert) {
                    contextWindowAlert = nil
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let session = sessionStore.sessions
                    .first(where: { $0.id == sessionID }) {
                    ExportOptionsView(
                        session: session,
                        chunks: Array(outputStore.chunks),
                        isPresented: $showExportSheet
                    )
                }
            }
            .sheet(isPresented: $showContextSheet) {
                ContextFileView(
                    projectRoot: viewModel.currentMetadata.workingDirectory,
                    isPresented: $showContextSheet
                )
            }
    }
}

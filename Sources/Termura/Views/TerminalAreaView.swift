import AppKit
import SwiftUI

/// Composes the terminal display, chunked output overlay, metadata panel, and editor input.
/// All @StateObject lifetimes are tied to the session via `.id(sessionID)` in the parent.
struct TerminalAreaView: View {

    let engine: SwiftTermEngine
    let sessionID: SessionID
    let theme: ThemeColors
    @ObservedObject var sessionStore: SessionStore
    let tokenCountingService: TokenCountingService
    var agentStateStore: AgentStateStore?

    @StateObject private var outputStore: OutputStore
    @StateObject private var modeController: InputModeController
    @StateObject private var viewModel: TerminalViewModel
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var timeline: SessionTimeline

    @State private var showTimeline = false
    @State private var showMetadata = true
    @State private var showAgentDashboard = false
    @State private var showExportSheet = false
    @State private var metadataPanelWidth: Double = AppConfig.UI.metadataPanelWidth

    /// Shared handle so the key-routing monitor can find the live EditorTextView.
    private let editorHandle = EditorViewHandle()
    /// Token returned by NSEvent.addLocalMonitorForEvents; retained for removal on disappear.
    @State private var keyEventMonitor: Any?

    // MARK: - Init

    init(
        engine: SwiftTermEngine,
        sessionID: SessionID,
        theme: ThemeColors,
        sessionStore: SessionStore,
        tokenCountingService: TokenCountingService,
        agentStateStore: AgentStateStore? = nil
    ) {
        self.engine = engine
        self.sessionID = sessionID
        self.theme = theme
        self.sessionStore = sessionStore
        self.tokenCountingService = tokenCountingService
        self.agentStateStore = agentStateStore

        let store = OutputStore(sessionID: sessionID)
        let modeCtrl = InputModeController()
        let tl = SessionTimeline()

        _outputStore = StateObject(wrappedValue: store)
        _modeController = StateObject(wrappedValue: modeCtrl)
        _timeline = StateObject(wrappedValue: tl)
        _viewModel = StateObject(wrappedValue: TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: sessionStore,
            outputStore: store,
            tokenCountingService: tokenCountingService,
            modeController: modeCtrl,
            agentStateStore: agentStateStore
        ))
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(
            engine: engine,
            modeController: modeCtrl
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left panel: Timeline or Agent Dashboard (mutually exclusive)
                if showAgentDashboard, let store = agentStateStore {
                    AgentDashboardView(agentStore: store) { sid in
                        sessionStore.activateSession(id: sid)
                    }
                    .transition(.move(edge: .leading))

                    Divider()
                } else if showTimeline && !outputStore.chunks.isEmpty {
                    TimelineView(timeline: timeline) { _ in }

                    Divider()
                }

                terminalAndOutputArea

                // Right panel: metadata
                if showMetadata {
                    ResizableDivider(
                        width: $metadataPanelWidth,
                        minWidth: AppConfig.UI.metadataPanelMinWidth,
                        maxWidth: AppConfig.UI.metadataPanelMaxWidth,
                        dragFactor: -1.0
                    )
                    SessionMetadataBarView(metadata: viewModel.currentMetadata)
                        .frame(width: metadataPanelWidth)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // EditorInputView is rendered inside terminalAndOutputArea as a ZStack overlay.
        }
        .onAppear {
            installKeyRouter()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 50_000_000)
                editorHandle.textView?.window?.makeFirstResponder(editorHandle.textView)
            }
        }
        .onDisappear { removeKeyRouter() }
        .sheet(item: $viewModel.pendingRiskAlert) { risk in
            InterventionAlertView(
                alert: risk,
                onProceed: { viewModel.pendingRiskAlert = nil },
                onCancel: { [engine] in
                    viewModel.pendingRiskAlert = nil
                    Task { await engine.send("\u{03}") }
                }
            )
        }
        .onChange(of: outputStore.chunks.count) { old, new in
            guard new > old, let latest = outputStore.chunks.last else { return }
            timeline.append(latest)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        showTimeline.toggle()
                        if showTimeline { showAgentDashboard = false }
                    }
                } label: {
                    Image(systemName: "timeline.selection")
                        .symbolVariant(showTimeline ? .fill : .none)
                        .help("Toggle Timeline (Cmd+Shift+L)")
                }
                .disabled(outputStore.chunks.isEmpty)
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation {
                        showAgentDashboard.toggle()
                        if showAgentDashboard { showTimeline = false }
                    }
                } label: {
                    Image(systemName: "cpu")
                        .symbolVariant(showAgentDashboard ? .fill : .none)
                        .help("Agent Dashboard (Cmd+Shift+A)")
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    withAnimation { showMetadata.toggle() }
                } label: {
                    Image(systemName: "sidebar.right")
                        .symbolVariant(showMetadata ? .fill : .none)
                        .help(showMetadata ? "Hide Session Info" : "Show Session Info")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showExport)) { notification in
            if let targetID = notification.object as? SessionID, targetID == sessionID {
                showExportSheet = true
            } else if notification.object == nil {
                showExportSheet = true
            }
        }
        .sheet(isPresented: $showExportSheet) {
            if let session = sessionStore.sessions.first(where: { $0.id == sessionID }) {
                ExportOptionsView(
                    session: session,
                    chunks: outputStore.chunks,
                    isPresented: $showExportSheet
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleTimeline)) { _ in
            withAnimation { showTimeline.toggle(); if showTimeline { showAgentDashboard = false } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleAgentDashboard)) { _ in
            withAnimation { showAgentDashboard.toggle(); if showAgentDashboard { showTimeline = false } }
        }
    }

    // MARK: - Terminal / output stack

    @ViewBuilder
    private var terminalAndOutputArea: some View {
        ZStack(alignment: .bottom) {
            TerminalContainerView(viewModel: viewModel, engine: engine, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Spacer()
                // Intervention toolbar when agent is active
                if let agentType = viewModel.currentMetadata.currentAgentType,
                   let agentStatus = viewModel.currentMetadata.currentAgentStatus {
                    interventionBar(agentType: agentType, status: agentStatus)
                }
                if modeController.mode == .editor {
                    editorOverlay
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// EditorInputView floating at the bottom of the terminal area.
    ///
    /// When `isInteractivePrompt` is true (Claude Code `>` visible), the overlay uses
    /// an opaque background matching the terminal colour — this physically covers the
    /// tool's own cursor line, giving a single-input-area experience identical to Warp's
    /// block-based layout but without any PTY resize side-effects.
    ///
    /// When false (shell prompt or idle), the background is semi-transparent with a
    /// top divider so the overlay reads as a floating card above the terminal.
    @ViewBuilder
    private var editorOverlay: some View {
        VStack(spacing: 0) {
            if !viewModel.isInteractivePrompt {
                Divider()
            }
            EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
                .frame(
                    minHeight: AppConfig.UI.editorMinHeightPoints,
                    maxHeight: AppConfig.UI.editorMaxHeightPoints
                )
                .clipShape(RoundedRectangle(cornerRadius: viewModel.isInteractivePrompt ? 0 : DS.Radius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: viewModel.isInteractivePrompt ? 0 : DS.Radius.lg)
                        .stroke(Color.secondary.opacity(viewModel.isInteractivePrompt ? 0 : DS.Opacity.border),
                                lineWidth: 1)
                )
                .padding(.horizontal, viewModel.isInteractivePrompt ? 0 : DS.Spacing.md)
                .padding(.bottom, viewModel.isInteractivePrompt ? 0 : DS.Spacing.md)
        }
        // Always opaque so the overlay is visible on top of the SwiftTerm NSView.
        // Interactive mode → match terminal background (seamless cover over `>`).
        // Normal mode → standard editor panel background.
        .background(
            viewModel.isInteractivePrompt
                ? Color(NSColor(theme.background))
                : Color(NSColor.windowBackgroundColor)
        )
    }

    // MARK: - Intervention toolbar

    private func interventionBar(agentType: AgentType, status: AgentStatus) -> some View {
        InterventionToolbarView(
            agentType: agentType,
            status: status,
            onPause: { Task { await engine.send("\u{03}") } },
            onResume: { Task { await engine.send("\n") } },
            onInsertDirective: { directive in Task { await engine.send(directive + "\n") } }
        )
        .padding(.horizontal, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
    }

    // MARK: - Key routing

    /// Ensures focus always lands on EditorTextView when a key is pressed.
    /// Ctrl+letter and Escape are handled by EditorTextView.keyDown → PTY directly.
    private func installKeyRouter() {
        let handle = editorHandle
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = NSApp.keyWindow,
                  let editorView = handle.textView,
                  editorView.window == window else { return event }
            // EditorTextView already has focus — pass through untouched.
            if window.firstResponder is EditorTextView { return event }
            // Let Cmd-key shortcuts (Cmd+Q, Cmd+W, etc.) pass through to the
            // menu system instead of being swallowed by the editor.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) { return event }
            // Steal focus and forward the event directly so the first keystroke
            // is not lost to SwiftTerm. Return nil to consume the original dispatch.
            window.makeFirstResponder(editorView)
            editorView.keyDown(with: event)
            return nil
        }
    }

    private func removeKeyRouter() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
}

import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalAreaView")

/// Composes the terminal display, chunked output overlay, metadata panel, and editor input.
/// All @StateObject lifetimes are tied to the session via `.id(sessionID)` in the parent.
struct TerminalAreaView: View {
    let engine: SwiftTermEngine
    let sessionID: SessionID
    let theme: ThemeColors
    @ObservedObject var sessionStore: SessionStore
    let tokenCountingService: TokenCountingService
    var agentStateStore: AgentStateStore?
    let isRestoredSession: Bool
    var contextInjectionService: ContextInjectionService?
    var sessionHandoffService: SessionHandoffService?
    /// When true (split pane mode), hides side panels and toolbar to save space.
    var isCompact: Bool = false

    @StateObject var outputStore: OutputStore
    @StateObject var modeController: InputModeController
    @StateObject var viewModel: TerminalViewModel
    @StateObject var editorViewModel: EditorViewModel
    @StateObject private var timeline: SessionTimeline

    @State var showTimeline = false
    @State var showMetadata = true
    @State private var showExportSheet = false
    @State var showContextSheet = false
    @State var contextFileExists = false
    @State private var metadataPanelWidth: Double = AppConfig.UI.metadataPanelWidth
    /// Tracks the measured height of the editor overlay so the terminal can add matching bottom padding.
    @State var editorOverlayHeight: CGFloat = 0
    /// User-adjustable editor height, draggable via the divider.
    @State var editorHeight: CGFloat = AppConfig.UI.editorMinHeightPoints
    @State var editorDragStart: CGFloat?

    /// Shared handle so the key-routing monitor can find the live EditorTextView.
    let editorHandle = EditorViewHandle()
    /// Token returned by NSEvent.addLocalMonitorForEvents; retained for removal on disappear.
    @State private var keyEventMonitor: Any?

    // MARK: - Init

    init(
        engine: SwiftTermEngine,
        sessionID: SessionID,
        theme: ThemeColors,
        sessionStore: SessionStore,
        tokenCountingService: TokenCountingService,
        agentStateStore: AgentStateStore? = nil,
        isRestoredSession: Bool = false,
        contextInjectionService: ContextInjectionService? = nil,
        sessionHandoffService: SessionHandoffService? = nil,
        isCompact: Bool = false
    ) {
        self.engine = engine
        self.sessionID = sessionID
        self.theme = theme
        self.sessionStore = sessionStore
        self.tokenCountingService = tokenCountingService
        self.agentStateStore = agentStateStore
        self.isRestoredSession = isRestoredSession
        self.contextInjectionService = contextInjectionService
        self.sessionHandoffService = sessionHandoffService
        self.isCompact = isCompact

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
            agentStateStore: agentStateStore,
            isRestoredSession: isRestoredSession,
            contextInjectionService: contextInjectionService,
            sessionHandoffService: sessionHandoffService
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
                if !isCompact {
                    // Left panel: Timeline
                    if showTimeline && !outputStore.chunks.isEmpty {
                        TimelineView(timeline: timeline) { _ in }

                        Divider()
                    }
                }

                terminalAndOutputArea

                // Right panel: metadata (hidden in compact/split mode)
                if !isCompact && showMetadata {
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
            .background(theme.background)

            // EditorInputView is rendered inside terminalAndOutputArea as a ZStack overlay.
        }
        .onAppear {
            installKeyRouter()
            checkContextFileExists()
            Task { @MainActor in
                do {
                    try await Task.sleep(
                        nanoseconds: AppConfig.UI.editorFocusDelayNanoseconds
                    )
                } catch is CancellationError {
                    return
                } catch {
                    logger.warning("Editor focus delay failed: \(error.localizedDescription)")
                    return
                }
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
        .sheet(item: $viewModel.contextWindowAlert) { alert in
            ContextWindowAlertView(alert: alert) {
                viewModel.contextWindowAlert = nil
            }
        }
        .onChange(of: outputStore.chunks.count) { old, new in
            guard new > old, let latest = outputStore.chunks.last else { return }
            timeline.append(latest)
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
            withAnimation { showTimeline.toggle() }
        }
        .sheet(isPresented: $showContextSheet) {
            ContextFileView(
                projectRoot: viewModel.currentMetadata.workingDirectory,
                isPresented: $showContextSheet
            )
        }
        .onChange(of: viewModel.currentMetadata.workingDirectory) { _, _ in
            checkContextFileExists()
        }
    }

    private func checkContextFileExists() {
        let dir = viewModel.currentMetadata.workingDirectory
        guard !dir.isEmpty else {
            contextFileExists = false
            return
        }
        let path = (dir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        contextFileExists = FileManager.default.fileExists(atPath: path)
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

// MARK: - PreferenceKey for editor overlay height

struct EditorOverlayHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

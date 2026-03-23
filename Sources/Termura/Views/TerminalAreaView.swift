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
    let isRestoredSession: Bool
    var contextInjectionService: ContextInjectionService?

    @StateObject private var outputStore: OutputStore
    @StateObject private var modeController: InputModeController
    @StateObject private var viewModel: TerminalViewModel
    @StateObject private var editorViewModel: EditorViewModel
    @StateObject private var timeline: SessionTimeline

    @State private var showTimeline = false
    @State private var showMetadata = true
    @State private var showAgentDashboard = false
    @State private var showExportSheet = false
    @State private var showContextSheet = false
    @State private var contextFileExists = false
    @State private var metadataPanelWidth: Double = AppConfig.UI.metadataPanelWidth
    /// Tracks the measured height of the editor overlay so the terminal can add matching bottom padding.
    @State private var editorOverlayHeight: CGFloat = 0

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
        agentStateStore: AgentStateStore? = nil,
        isRestoredSession: Bool = false,
        contextInjectionService: ContextInjectionService? = nil
    ) {
        self.engine = engine
        self.sessionID = sessionID
        self.theme = theme
        self.sessionStore = sessionStore
        self.tokenCountingService = tokenCountingService
        self.agentStateStore = agentStateStore
        self.isRestoredSession = isRestoredSession
        self.contextInjectionService = contextInjectionService

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
            contextInjectionService: contextInjectionService
        ))
        _editorViewModel = StateObject(wrappedValue: EditorViewModel(
            engine: engine,
            modeController: modeCtrl
        ))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            projectPathBar

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
            checkContextFileExists()
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

    // MARK: - Project path bar

    /// Whether an AI agent is currently running in this session.
    private var isAgentBusy: Bool {
        viewModel.currentMetadata.currentAgentType != nil
    }

    private var projectPathBar: some View {
        HStack(spacing: DS.Spacing.smMd) {
            Button {
                openDirectoryPicker()
            } label: {
                Image(systemName: "folder.fill")
                    .font(DS.Font.caption)
                    .foregroundColor(isAgentBusy ? .secondary.opacity(DS.Opacity.dimmed) : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isAgentBusy)
            .help(isAgentBusy ? "Agent is running — cannot change directory" : "Change working directory")

            Button {
                openDirectoryPicker()
            } label: {
                Text(abbreviatedWorkingDirectory)
                    .font(DS.Font.labelMono)
                    .foregroundColor(.primary.opacity(DS.Opacity.strong))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .disabled(isAgentBusy)
            .onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(isAgentBusy ? "Agent is running" : "Switch working directory")

            Button { showContextSheet = true } label: {
                Image(systemName: "doc.text")
                    .font(DS.Font.caption)
                    .foregroundColor(
                        contextFileExists
                            ? .accentColor
                            : .secondary.opacity(DS.Opacity.dimmed)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!contextFileExists)
            .help("Session context (context.md)")

            if isAgentBusy {
                Spacer()
                HStack(spacing: DS.Spacing.sm) {
                    Circle()
                        .fill(.orange)
                        .frame(width: DS.Size.dotSmall, height: DS.Size.dotSmall)
                    Text("Agent active")
                        .font(DS.Font.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.smMd)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func revealInFinder() {
        let path = viewModel.currentMetadata.workingDirectory
        guard !path.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func openDirectoryPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Select"
        panel.title = "Choose Project Directory"
        panel.message = "Select a directory to switch the terminal working directory"
        panel.directoryURL = URL(fileURLWithPath: viewModel.currentMetadata.workingDirectory)

        guard let window = NSApp.keyWindow else { return }
        let eng = engine
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            // Silent directory switch: cd + clear so the user never sees the command.
            let cdCommand = "cd \(url.path.shellEscaped) && clear\n"
            Task { @MainActor in await eng.send(cdCommand) }
        }
    }

    private var abbreviatedWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = viewModel.currentMetadata.workingDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Terminal / output stack

    @ViewBuilder
    private var terminalAndOutputArea: some View {
        ZStack(alignment: .bottom) {
            TerminalContainerView(viewModel: viewModel, engine: engine, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Reserve space at the bottom so terminal content is not hidden behind the overlay.
                .padding(.bottom, modeController.mode == .editor ? editorOverlayHeight : 0)

            VStack(spacing: 0) {
                Spacer()
                // Intervention toolbar when agent is active
                if let agentType = viewModel.currentMetadata.currentAgentType,
                   let agentStatus = viewModel.currentMetadata.currentAgentStatus {
                    interventionBar(agentType: agentType, status: agentStatus)
                }
                if modeController.mode == .editor {
                    editorOverlay
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: EditorOverlayHeightKey.self,
                                    value: geo.size.height
                                )
                            }
                        )
                }
            }
        }
        .onPreferenceChange(EditorOverlayHeightKey.self) { height in
            editorOverlayHeight = height
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
        let isFloating = !viewModel.isInteractivePrompt
        let radius: CGFloat = isFloating ? DS.Radius.xl : 0

        VStack(spacing: 0) {
            if isFloating {
                Divider()
            }
            EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
                .frame(
                    minHeight: AppConfig.UI.editorMinHeightPoints,
                    maxHeight: AppConfig.UI.editorMaxHeightPoints
                )
                .clipShape(RoundedRectangle(cornerRadius: radius))
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(
                            Color.secondary.opacity(isFloating ? DS.Opacity.softBorder : 0),
                            lineWidth: 0.5
                        )
                )
                .padding(.horizontal, isFloating ? DS.Spacing.lg : 0)
                .padding(.bottom, isFloating ? DS.Spacing.md : 0)
                .if(isFloating) { $0.floatingCard() }
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
        .floatingCard()
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.bottom, DS.Spacing.smMd)
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

private struct EditorOverlayHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Shell escape helper

private extension String {
    /// Wraps the string in single quotes with proper escaping for shell use.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

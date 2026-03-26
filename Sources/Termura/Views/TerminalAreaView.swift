import AppKit
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalAreaView")

/// Composes the terminal display, chunked output overlay, metadata panel, and editor input.
/// All @StateObject lifetimes are tied to the session via `.id(sessionID)` in the parent.
struct TerminalAreaView: View {
    let engine: SwiftTermEngine
    let sessionID: SessionID
    /// When true (split pane mode), hides side panels and toolbar to save space.
    var isCompact: Bool = false

    @EnvironmentObject var projectContext: ProjectContext
    @EnvironmentObject var commandRouter: CommandRouter
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var fontSettings: FontSettings
    /// Per-session state container — owned by `ProjectContext.sessionViewStates`,
    /// received here as `@ObservedObject` to avoid the fragile `@StateObject`-in-init pattern.
    @ObservedObject var state: SessionViewState

    // MARK: - Convenience accessors

    var outputStore: OutputStore { state.outputStore }
    var modeController: InputModeController { state.modeController }
    var viewModel: TerminalViewModel { state.viewModel }
    var editorViewModel: EditorViewModel { state.editorViewModel }
    var timeline: SessionTimeline { state.timeline }

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

    // MARK: - Body

    var body: some View {
        mainLayout
            .onAppear { onViewAppear() }
            .onDisappear { removeKeyRouter() }
            .modifier(TerminalAreaSheets(
                riskAlert: $state.viewModel.pendingRiskAlert,
                contextWindowAlert: $state.viewModel.contextWindowAlert,
                showExportSheet: $showExportSheet,
                showContextSheet: $showContextSheet,
                engine: engine,
                sessionID: sessionID,
                projectContext: projectContext,
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
            .onChange(of: commandRouter.toggleTimelineTick) { _, _ in
                withAnimation { showTimeline.toggle() }
            }
    }

    // MARK: - Extracted layout

    private var mainLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !isCompact {
                    if showTimeline && !outputStore.chunks.isEmpty {
                        TimelineView(timeline: timeline) { _ in }
                        Divider()
                    }
                }

                terminalAndOutputArea

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
            .background(themeManager.current.background)
        }
    }

    // MARK: - Lifecycle

    private func onViewAppear() {
        installKeyRouter()
        checkContextFileExists()
        editorViewModel.onCommandSubmit = { [weak viewModel] cmd in
            viewModel?.detectAgentFromCommand(cmd)
        }
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

    private func checkContextFileExists() {
        let dir = viewModel.currentMetadata.workingDirectory
        guard !dir.isEmpty else {
            contextFileExists = false
            return
        }
        let path = (dir as NSString)
            .appendingPathComponent(AppConfig.SessionHandoff.directoryName)
            .appending("/\(AppConfig.SessionHandoff.contextFileName)")
        Task.detached {
            let exists = FileManager.default.fileExists(atPath: path)
            await MainActor.run { contextFileExists = exists }
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
        let handle = editorHandle
        let modeCtrl = modeController
        let termEngine = engine
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            dispatchPrecondition(condition: .onQueue(.main))

            guard let window = NSApp.keyWindow,
                  let editorView = handle.textView,
                  editorView.window == window else { return event }
            // Let Cmd-key shortcuts (Cmd+Q, Cmd+W, etc.) always pass through to the
            // menu system — regardless of input mode.
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) { return event }
            // In passthrough mode the editor is hidden — route keys to the terminal.
            if modeCtrl.mode == .passthrough {
                let termView = termEngine.terminalView
                if window.firstResponder !== termView {
                    window.makeFirstResponder(termView)
                }
                termView.keyDown(with: event)
                return nil
            }
            // EditorTextView already has focus — pass through untouched.
            if window.firstResponder is EditorTextView { return event }
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

// MARK: - Sheet modifiers

private struct TerminalAreaSheets: ViewModifier {
    @Binding var riskAlert: RiskAlert?
    @Binding var contextWindowAlert: ContextWindowAlert?
    @Binding var showExportSheet: Bool
    @Binding var showContextSheet: Bool
    let engine: SwiftTermEngine
    let sessionID: SessionID
    let projectContext: ProjectContext
    let outputStore: OutputStore
    let viewModel: TerminalViewModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $riskAlert) { risk in
                InterventionAlertView(
                    alert: risk,
                    onProceed: { riskAlert = nil },
                    onCancel: { [engine] in
                        riskAlert = nil
                        Task { await engine.send("\u{03}") }
                    }
                )
            }
            .sheet(item: $contextWindowAlert) { alert in
                ContextWindowAlertView(alert: alert) {
                    contextWindowAlert = nil
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let session = projectContext.sessionStore.sessions
                    .first(where: { $0.id == sessionID }) {
                    ExportOptionsView(
                        session: session,
                        chunks: outputStore.chunks,
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

// MARK: - PreferenceKey for editor overlay height

struct EditorOverlayHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

import AppKit
import SwiftUI

extension TerminalAreaView {
    // MARK: - Project path bar

    /// Whether an AI agent is currently running in this session.
    var isAgentBusy: Bool {
        viewModel.currentMetadata.currentAgentType != nil
    }

    var projectPathBar: some View {
        HStack(spacing: 0) {
            Button {
                openDirectoryPicker()
            } label: {
                Text(viewModel.currentMetadata.workingDirectory)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.strong))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .disabled(isAgentBusy)
            .onHover { hovering in
                if hovering && !isAgentBusy {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(isAgentBusy ? "Agent is running" : "Switch working directory")

            if contextFileExists {
                Button { showContextSheet = true } label: {
                    Image(systemName: "doc.text")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, AppUI.Spacing.smMd)
                .help("Session context (context.md)")
            }

            Spacer()

            if isAgentBusy {
                HStack(spacing: AppUI.Spacing.sm) {
                    Circle()
                        .fill(.orange)
                        .frame(width: AppUI.Size.dotSmall, height: AppUI.Size.dotSmall)
                    Text("Agent active")
                        .font(AppUI.Font.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !outputStore.chunks.isEmpty {
                Button {
                    withAnimation { showTimeline.toggle() }
                } label: {
                    Image(systemName: "timeline.selection")
                        .symbolVariant(showTimeline ? .fill : .none)
                        .font(.system(size: 13))
                        .foregroundColor(showTimeline ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help("Toggle Timeline")
            }

            Button {
                withAnimation { showMetadata.toggle() }
            } label: {
                Image(systemName: "inset.filled.rightthird.rectangle")
                    .font(.system(size: 13))
                    .foregroundColor(showMetadata ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(showMetadata ? "Hide Session Info" : "Show Session Info")
        }
        .frame(height: AppConfig.UI.projectPathBarHeight)
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
    }

    func revealInFinder() {
        let path = viewModel.currentMetadata.workingDirectory
        guard !path.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    func openDirectoryPicker() {
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

    var abbreviatedWorkingDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = viewModel.currentMetadata.workingDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Intervention toolbar

    func interventionBar(agentType: AgentType, status: AgentStatus) -> some View {
        InterventionToolbarView(
            agentType: agentType,
            status: status,
            onPause: { Task { await engine.send("\u{03}") } },
            onResume: { Task { await engine.send("\n") } },
            onInsertDirective: { directive in Task { await engine.send(directive + "\n") } }
        )
        .floatingCard()
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.bottom, AppUI.Spacing.smMd)
    }

    // MARK: - Terminal / output stack

    @ViewBuilder
    var terminalAndOutputArea: some View {
        ZStack {
            VStack(spacing: 0) {
                if !isCompact {
                    projectPathBar
                }
                TerminalContainerView(viewModel: viewModel, engine: engine, theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, AppUI.Spacing.xxl)
                    // Reserve space at the bottom so terminal content is not hidden behind the overlay.
                    .padding(.bottom, modeController.mode == .editor ? editorOverlayHeight : 0)
            }

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
        .background(theme.background)
    }

}

extension String {
    /// Wraps the string in single quotes with proper escaping for shell use.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

extension TerminalAreaView {
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
    var editorOverlay: some View {
        VStack(spacing: 0) {
            editorDividerHandle
            EditorInputView(viewModel: editorViewModel, viewHandle: editorHandle)
                .frame(height: editorHeight)
                .padding(.horizontal, AppUI.Spacing.xxl)
                .padding(.vertical, AppUI.Spacing.xl)
        }
        .background(theme.background)
    }

    /// Draggable divider between terminal and editor input.
    private var editorDividerHandle: some View {
        ZStack {
            Divider()
            Color.clear
                .frame(height: AppConfig.UI.editorDividerHandleHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if editorDragStart == nil { editorDragStart = editorHeight }
                            // Dragging up → negative translation → increase editor height
                            let proposed = (editorDragStart ?? editorHeight) - value.translation.height
                            var transaction = Transaction()
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                editorHeight = min(max(proposed, AppConfig.UI.editorMinHeightPoints), AppConfig.UI.editorMaxHeightPoints)
                            }
                        }
                        .onEnded { _ in editorDragStart = nil }
                )
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeUpDown.push()
                    } else {
                        NSCursor.pop()
                    }
                }
        }
    }
}

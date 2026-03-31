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
            if localUI.contextFileExists {
                Button { localUI.showContextSheet = true } label: {
                    Image(systemName: "distribute.vertical")
                        .font(AppUI.Font.toolbarIcon)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.trailing, AppUI.Spacing.xxl)
                .help("Session context (context.md)")
            }

            pathLabel

            Spacer()

            if !hideToolbarButtons {
                toolbarButtons
            }
        }
        .frame(height: AppConfig.UI.projectPathBarHeight)
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.top, AppUI.Spacing.md)
        .padding(.bottom, AppUI.Spacing.smMd)
    }

    private var pathLabel: some View {
        Button {
            openDirectoryPicker()
        } label: {
            HStack(spacing: AppUI.Spacing.sm) {
                if let filePath = viewModel.currentMetadata.agentActiveFilePath,
                   viewModel.currentMetadata.currentAgentStatus == .toolRunning {
                    Text(abbreviatedFilePath(filePath))
                        .font(AppUI.Font.pathMono)
                        .foregroundColor(.accentColor.opacity(AppUI.Opacity.strong))
                        .lineLimit(1)
                        .truncationMode(.head)
                } else {
                    Text(abbreviatedWorkingDirectory)
                        .font(AppUI.Font.pathMono)
                        .foregroundColor(.secondary.opacity(AppUI.Opacity.strong))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
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
    }

    /// Returns path relative to working directory if it starts with it, else abbreviates home.
    func abbreviatedFilePath(_ path: String) -> String {
        let wd = viewModel.currentMetadata.workingDirectory
        if !wd.isEmpty, path.hasPrefix(wd) {
            let relative = path.dropFirst(wd.count)
            return relative.hasPrefix("/") ? String(relative.dropFirst()) : String(relative)
        }
        let home = AppConfig.Paths.homeDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    /// Reflects whether the session-info panel is currently visible.
    /// In dual-pane mode the toggle is global; in single-pane it is per-session.
    private var infoVisible: Bool {
        commandRouter.isDualPaneActive ? commandRouter.showDualPaneMetadata : state.showMetadata
    }

    @ViewBuilder
    private var toolbarButtons: some View {
        Button {
            commandRouter.toggleComposer()
        } label: {
            Image(systemName: "menubar.dock.rectangle")
                .font(AppUI.Font.toolbarIcon)
                .foregroundColor(commandRouter.showComposer ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help("Composer (Cmd+K)")

        Spacer().frame(width: AppUI.Spacing.xxl)

        Button {
            commandRouter.toggleDualPane()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(AppUI.Font.toolbarIcon)
                .foregroundColor(commandRouter.isDualPaneActive ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(commandRouter.isDualPaneActive ? "Exit Split View" : "Split View")

        Spacer().frame(width: AppUI.Spacing.xxl)

        Button {
            if commandRouter.isDualPaneActive {
                commandRouter.showDualPaneMetadata.toggle()
            } else {
                withAnimation { state.showMetadata.toggle() }
            }
        } label: {
            Image(systemName: "info.windshield")
                .font(AppUI.Font.toolbarIcon)
                .foregroundColor(infoVisible ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(infoVisible ? "Hide Inspector (Cmd+Shift+I)" : "Show Inspector (Cmd+Shift+I)")
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
        panel.prompt = String(localized: "Select")
        panel.title = String(localized: "Choose Project Directory")
        panel.message = String(localized: "Select a directory to switch the terminal working directory")
        panel.directoryURL = URL(fileURLWithPath: viewModel.currentMetadata.workingDirectory)

        guard let window = NSApp.keyWindow else { return }
        let eng = engine
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            // Silent directory switch: cd + clear so the user never sees the command.
            let cdCommand = "cd \(url.path.shellEscaped) && clear\r"
            Task { @MainActor in await eng.send(cdCommand) }
        }
    }

    var abbreviatedWorkingDirectory: String {
        let home = AppConfig.Paths.homeDirectory
        let path = viewModel.currentMetadata.workingDirectory
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    // MARK: - Terminal / output stack

    @ViewBuilder
    var terminalAndOutputArea: some View {
        VStack(spacing: 0) {
            if !isCompact {
                projectPathBar
            }
            ZStack(alignment: .bottom) {
                TerminalContainerView(
                    viewModel: viewModel,
                    engine: engine,
                    theme: themeManager.current,
                    fontFamily: fontSettings.terminalFontFamily,
                    fontSize: fontSettings.terminalFontSize,
                    isComposerActive: commandRouter.showComposer && isFocusedPane
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppUI.Spacing.xxl)
                .background(themeManager.current.background)

                if commandRouter.showComposer && isFocusedPane {
                    // VStack-based bottom sheet: backdrop fills the space above the composer,
                    // composer sits at the fixed bottom. This avoids GeometryReader, which
                    // has a known async sizing issue inside ZStack+NSViewRepresentable hierarchies
                    // (geo.size can be stale on the first layout pass, causing the backdrop height
                    // to be wrong and the composer to appear misaligned).
                    VStack(spacing: 0) {
                        // Backdrop — covers the terminal above the composer.
                        // Uses AppKitClickableOverlay (not .onTapGesture) because SwiftTerm's
                        // TerminalDragContainerView and EditorTextView are real AppKit NSViews
                        // that AppKit hitTest routes events before SwiftUI gestures can fire.
                        themeManager.current.background
                            .opacity(AppUI.Opacity.strong)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(AppKitClickableOverlay(action: { commandRouter.dismissComposer() }))
                            .transition(.opacity.animation(.easeOut(duration: AppUI.Animation.fadeOut)))

                        ComposerOverlayView(
                            editorViewModel: editorViewModel,
                            editorHandle: editorHandle,
                            isNotesActive: commandRouter.isComposerNotesActive,
                            onToggleNotes: { commandRouter.toggleComposerNotes() },
                            onDismiss: { commandRouter.dismissComposer() }
                        )
                        .onAppear {
                            let vm = editorViewModel
                            commandRouter.composerInsertHandler = { text in
                                vm.appendText("\n" + text)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom)
                                .animation(.spring(
                                    response: AppConfig.UI.composerSpringResponse,
                                    dampingFraction: AppConfig.UI.composerSpringDamping
                                )),
                            removal: .opacity
                                .animation(.easeOut(duration: AppConfig.UI.composerDismissDuration))
                        ))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.current.background)
    }
}

extension String {
    /// Wraps the string in single quotes with proper escaping for shell use.
    var shellEscaped: String {
        "'" + replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

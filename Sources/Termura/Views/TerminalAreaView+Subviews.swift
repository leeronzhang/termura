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
            pathLabel

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
            Text(viewModel.currentMetadata.workingDirectory)
                .font(AppUI.Font.pathMono)
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
            withAnimation { showMetadata.toggle() }
        } label: {
            Image(systemName: "info.windshield")
                .font(AppUI.Font.toolbarIcon)
                .foregroundColor(showMetadata ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
        .help(showMetadata ? "Hide Session Info" : "Show Session Info")
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
                    fontSize: fontSettings.terminalFontSize
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, AppUI.Spacing.xxl)
                .background(themeManager.current.background)

                if commandRouter.showComposer && isFocusedPane {
                    // Backdrop — tapping dismisses composer (pure SwiftUI, no NSEvent monitor).
                    Color.black.opacity(AppUI.Opacity.strong)
                        .contentShape(Rectangle())
                        .onTapGesture { commandRouter.dismissComposer() }
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
                    .transition(
                        .move(edge: .bottom)
                            .animation(.spring(response: 0.35, dampingFraction: 0.85))
                    )
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

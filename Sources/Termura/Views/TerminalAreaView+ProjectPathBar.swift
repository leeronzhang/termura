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
    var toolbarButtons: some View {
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

        if commandRouter.isDualPaneActive {
            Spacer().frame(width: AppUI.Spacing.xxl)

            Button {
                commandRouter.pendingCommand = .swapPanes
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(AppUI.Font.toolbarIcon)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Swap Panes (Ctrl+Shift+S)")
        }

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

        let vm = viewModel
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            vm.changeDirectory(to: url)
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
}

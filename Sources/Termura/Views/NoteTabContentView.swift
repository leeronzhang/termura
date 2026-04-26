import AppKit
import SwiftUI

/// Standalone view for the note-editor tab content.
///
/// Extracted from `MainView+Content.noteEditorView()` so the `.onChange` on
/// `notesViewModel.editingTitle` lives outside the `MainView+*.swift` context and
/// does not count against MainView's 5-onChange budget (CLAUDE.md §5.5).
struct NoteTabContentView: View {
    let noteID: NoteID
    /// When false (non-focused pane in note dual-pane mode), content is read-only.
    var isFocusedPane: Bool = true
    /// When true, split-view toolbar buttons are hidden (left pane in dual mode).
    var hideToolbarButtons: Bool = false
    @Environment(\.notesViewModel) var notesViewModel
    @Environment(\.commandRouter) var commandRouter
    @Environment(\.themeManager) var themeManager
    @Environment(\.webViewPool) var webViewPool
    @Environment(\.webRendererBridge) var webRendererBridge
    @Environment(\.fontSettings) var fontSettings
    var notes: Bindable<NotesViewModel>
    let onTitleChange: (NoteID, String) -> Void
    /// Called when the non-focused pane is tapped to request focus.
    var onFocusRequest: (() -> Void)?

    @FocusState private var isTitleFocused: Bool
    @State private var viewMode: NoteViewMode = .edit

    /// Direct lookup for non-focused pane — avoids stale snapshot race with WKWebView loading.
    private var inactiveNote: NoteRecord? {
        notesViewModel.notes.first { $0.id == noteID }
    }

    var body: some View {
        VStack(spacing: 0) {
            noteHeader
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if notesViewModel.notes.isEmpty {
                await notesViewModel.loadNotes()
            }
            if isFocusedPane {
                notesViewModel.selectNote(id: noteID)
                if notesViewModel.editingTitle == "Untitled" {
                    isTitleFocused = true
                }
            }
        }
        .onChange(of: notesViewModel.editingTitle) { _, newTitle in
            if isFocusedPane { onTitleChange(noteID, newTitle) }
        }
        .onChange(of: isFocusedPane) { _, focused in
            if focused { notesViewModel.selectNote(id: noteID) }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isFocusedPane {
            focusedContent
        } else {
            readOnlyContent
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { onFocusRequest?() }
                }
        }
    }

    @ViewBuilder
    private var focusedContent: some View {
        switch viewMode {
        case .edit:
            CodeEditorTextViewRepresentable(
                text: notes.editingBody,
                isModified: .constant(false),
                onSave: {},
                fontFamily: fontSettings.terminalFontFamily,
                fontSize: fontSettings.editorFontSize,
                language: "markdown",
                autoFocus: false
            )
        case .reading:
            VStack(spacing: 0) {
                NoteRenderedView(
                    pool: webViewPool,
                    bridge: webRendererBridge,
                    theme: themeManager.current,
                    markdown: notesViewModel.editingBody,
                    references: notesViewModel.selectedNote?.references ?? [],
                    backlinks: notesViewModel.selectedNoteBacklinks.map(\.title),
                    projectURL: noteBaseURL(for: notesViewModel.selectedNote),
                    onOpenBacklink: { notesViewModel.navigateToBacklink(title: $0) }
                )
                BacklinksPanel(
                    backlinks: notesViewModel.selectedNoteBacklinks,
                    onOpenBacklink: { notesViewModel.navigateToBacklink(title: $0) }
                )
            }
        }
    }

    /// Non-focused pane always renders in reading mode from the notes array.
    private var readOnlyContent: some View {
        VStack(spacing: 0) {
            NoteRenderedView(
                pool: webViewPool,
                bridge: webRendererBridge,
                theme: themeManager.current,
                markdown: inactiveNote?.body ?? "",
                references: inactiveNote?.references ?? [],
                backlinks: notesViewModel.selectedNoteBacklinks.map(\.title),
                projectURL: noteBaseURL(for: inactiveNote),
                onOpenBacklink: { notesViewModel.navigateToBacklink(title: $0) }
            )
            BacklinksPanel(
                backlinks: notesViewModel.selectedNoteBacklinks,
                onOpenBacklink: { notesViewModel.navigateToBacklink(title: $0) }
            )
        }
    }

    private func noteBaseURL(for note: NoteRecord?) -> URL {
        let fallback = notesViewModel.notesDirectoryURL
            ?? URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
        guard let note, note.isFolder,
              let dir = notesViewModel.notesDirectoryURL else { return fallback }
        return dir.appendingPathComponent(NoteFileService.folderName(for: note))
    }

    // MARK: - Header

    private var noteHeader: some View {
        HStack(spacing: 0) {
            if isFocusedPane {
                TextField("Title", text: notes.editingTitle)
                    .font(AppUI.Font.title1Semibold)
                    .textFieldStyle(.plain)
                    .focused($isTitleFocused)
            } else {
                Text((inactiveNote?.title).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled")
                    .font(AppUI.Font.title1Semibold)
                    .foregroundColor(.primary)
            }
            Spacer()
            if isFocusedPane {
                noteModeToggle
                Spacer().frame(width: AppUI.Spacing.xxl)
                noteFavoriteButton
            }
            if !hideToolbarButtons {
                Spacer().frame(width: AppUI.Spacing.xxl)
                splitToggleButton
                if commandRouter.isNoteDualPaneActive {
                    Spacer().frame(width: AppUI.Spacing.xxl)
                    swapPanesButton
                }
            }
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    // MARK: - Toolbar buttons

    private var noteModeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewMode = (viewMode == .edit) ? .reading : .edit
            }
        } label: {
            Image(systemName: viewMode == .edit ? "eye" : "highlighter")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
        .accessibilityLabel(viewMode == .edit ? "Switch to Reading mode" : "Switch to Edit mode")
    }

    private var noteFavoriteButton: some View {
        let isFav = notesViewModel.selectedNote?.isFavorite ?? false
        return Button {
            notesViewModel.toggleFavorite(id: noteID)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(AppUI.Font.body)
                .foregroundColor(isFav ? .brandGreen : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
        .accessibilityLabel(isFav ? "Remove from favorites" : "Add to favorites")
    }

    private var splitToggleButton: some View {
        Button {
            commandRouter.toggleDualPane()
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .font(AppUI.Font.body)
                .foregroundColor(commandRouter.isNoteDualPaneActive ? .brandGreen : .secondary)
        }
        .buttonStyle(.plain)
        .help(commandRouter.isNoteDualPaneActive ? "Exit Split View" : "Split View")
    }

    private var swapPanesButton: some View {
        Button {
            commandRouter.pendingCommand = .swapPanes
        } label: {
            Image(systemName: "arrow.left.arrow.right")
                .font(AppUI.Font.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help("Swap Panes")
    }
}

import AppKit
import SwiftUI

struct NotesSplitView: View {
    @Bindable var viewModel: NotesViewModel
    @Environment(\.themeManager) var themeManager
    @Environment(\.webViewPool) var webViewPool
    @Environment(\.webRendererBridge) var webRendererBridge
    @Environment(\.fontSettings) var fontSettings

    @FocusState private var isTitleFocused: Bool
    @State private var viewMode: NoteViewMode = .edit

    var body: some View {
        HSplitView {
            noteList
                .frame(minWidth: 180, maxWidth: 260)
            editorPane
                .frame(minWidth: 300, maxWidth: .infinity)
        }
        .task { await viewModel.loadNotes() }
    }

    // MARK: - Note list

    private var noteList: some View {
        VStack(spacing: 0) {
            noteListHeader
            List(viewModel.notes, selection: $viewModel.selectedNoteID) { note in
                Text(note.title.isEmpty ? "Untitled" : note.title)
                    .tag(note.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            Task { await viewModel.deleteNote(id: note.id) }
                        }
                    }
            }
            .listStyle(.sidebar)
            .onChange(of: viewModel.selectedNoteID) { _, newID in
                if let id = newID {
                    viewModel.selectNote(id: id)
                    if viewModel.editingTitle == "Untitled" {
                        isTitleFocused = true
                    }
                }
            }
        }
    }

    private var noteListHeader: some View {
        HStack {
            Text("Notes")
                .panelHeaderStyle()
            Spacer()
            Button {
                viewModel.createNote()
            } label: {
                Image(systemName: "plus").font(AppUI.Font.body)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppUI.Spacing.lg)
        .padding(.vertical, AppUI.Spacing.md)
    }

    /// Base URL for resolving relative image paths in the rendered note.
    /// Folder notes use the folder directory; flat notes use the notes root.
    private var noteBaseURL: URL {
        let fallback = viewModel.notesDirectoryURL
            ?? URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
        guard let note = viewModel.selectedNote, note.isFolder,
              let dir = viewModel.notesDirectoryURL else { return fallback }
        return dir.appendingPathComponent(NoteFileService.folderName(for: note))
    }

    // MARK: - Editor

    @ViewBuilder
    private var editorPane: some View {
        if let noteID = viewModel.selectedNoteID {
            VStack(spacing: 0) {
                noteHeader(noteID: noteID)
                Divider()
                splitContent(noteID: noteID)
            }
        } else {
            VStack(spacing: AppUI.Spacing.smMd) {
                Image(systemName: "text.rectangle")
                    .font(AppUI.Font.hero)
                    .foregroundColor(.secondary.opacity(AppUI.Opacity.muted))
                Text("Select or create a note")
                    .font(AppUI.Font.label)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func splitContent(noteID: NoteID) -> some View {
        switch viewMode {
        case .edit:
            CodeEditorTextViewRepresentable(
                text: $viewModel.editingBody,
                isModified: .constant(false),
                onSave: {},
                fontFamily: fontSettings.terminalFontFamily,
                fontSize: fontSettings.editorFontSize,
                language: "markdown",
                autoFocus: false
            )
            .id(noteID)
        case .reading:
            NoteRenderedView(
                pool: webViewPool,
                bridge: webRendererBridge,
                theme: themeManager.current,
                markdown: viewModel.editingBody,
                references: viewModel.selectedNote?.references ?? [],
                backlinks: viewModel.selectedNoteBacklinks.map(\.title),
                projectURL: noteBaseURL,
                onOpenBacklink: { viewModel.navigateToBacklink(title: $0) }
            )
            .id(noteID)
        }
    }

    private func noteHeader(noteID: NoteID) -> some View {
        HStack(spacing: 0) {
            TextField("Title", text: $viewModel.editingTitle)
                .font(AppUI.Font.title1Semibold)
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
            Spacer()
            splitModeToggle
            Spacer().frame(width: AppUI.Spacing.xxl)
            splitFavoriteButton(noteID: noteID)
        }
        .padding(.horizontal, AppUI.Spacing.xxl)
        .padding(.vertical, AppUI.Spacing.md)
    }

    private var splitModeToggle: some View {
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

    private func splitFavoriteButton(noteID: NoteID) -> some View {
        let isFav = viewModel.selectedNote?.isFavorite ?? false
        return Button {
            viewModel.toggleFavorite(id: noteID)
        } label: {
            Image(systemName: isFav ? "star.fill" : "star")
                .font(AppUI.Font.body)
                .foregroundColor(isFav ? .brandGreen : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFav ? "Remove from favorites" : "Add to favorites")
    }
}

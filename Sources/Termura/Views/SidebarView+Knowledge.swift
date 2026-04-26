import Foundation
import SwiftUI

/// Knowledge sub-view inside the Project sidebar tab.
/// Lists `.termura/knowledge/{sources,log,attachments}` contents grouped by category.
/// Embedded by `SidebarProjectContent` when the inline view-mode toggle is set to `.knowledge`.
struct SidebarKnowledgeContent: View {
    let discovery: ProjectDiscovery
    var onOpenFile: ((String, FileOpenMode) -> Void)?

    private struct CategoryGroup: Identifiable {
        let id: String
        let files: [KnowledgeFileEntry]
    }

    @State private var sourceGroups: [CategoryGroup] = []
    @State private var logGroups: [CategoryGroup] = []
    @State private var attachments: [KnowledgeFileEntry] = []

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppUI.Spacing.sm) {
                sourcesSection
                logSection
                attachmentsSection
            }
            .padding(.leading, AppUI.Spacing.xxxl)
            .padding(.trailing, AppUI.Spacing.lg)
            .padding(.bottom, AppUI.Spacing.xxl)
        }
        .task { reload() }
    }

    // MARK: - Sections

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Sources")
            if sourceGroups.isEmpty {
                sectionPlaceholder("No source categories")
            } else {
                ForEach(sourceGroups) { group in
                    KnowledgeGroupSection(
                        title: group.id,
                        files: group.files,
                        onOpenFile: { open(entry: $0, in: discovery.sourcesDirectory) }
                    )
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Log")
            if logGroups.isEmpty {
                sectionPlaceholder("No log entries yet")
            } else {
                ForEach(logGroups) { group in
                    KnowledgeGroupSection(
                        title: group.id,
                        files: group.files,
                        onOpenFile: { open(entry: $0, in: discovery.logDirectory) }
                    )
                }
            }
        }
    }

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Attachments")
            if attachments.isEmpty {
                sectionPlaceholder("No attachments yet")
            } else {
                KnowledgeGroupSection(
                    title: "All",
                    files: attachments,
                    onOpenFile: { open(entry: $0, in: discovery.attachmentsDirectory) }
                )
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .panelHeaderStyle()
            .padding(.top, AppUI.Spacing.md)
            .padding(.bottom, AppUI.Spacing.xs)
    }

    private func sectionPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(AppUI.Font.caption)
            .foregroundColor(.secondary.opacity(AppUI.Opacity.dimmed))
            .padding(.vertical, AppUI.Spacing.sm)
    }

    // MARK: - Loading

    private func reload() {
        sourceGroups = KnowledgeFileLister
            .listSubdirGroups(in: discovery.sourcesDirectory)
            .map { CategoryGroup(id: $0.category, files: $0.files) }
        logGroups = KnowledgeFileLister
            .listSubdirGroups(in: discovery.logDirectory, descending: true)
            .map { CategoryGroup(id: $0.category, files: $0.files) }
        attachments = KnowledgeFileLister.listFlat(
            in: discovery.attachmentsDirectory, category: "all"
        )
    }

    // MARK: - Open

    private func open(entry: KnowledgeFileEntry, in baseDir: URL) {
        guard !entry.isDirectory else { return }
        let absolute = baseDir.appendingPathComponent(entry.relativePath)
            .resolvingSymlinksInPath().path
        let rootPath = discovery.projectRoot.resolvingSymlinksInPath().path
        let relativeToProject: String = {
            if absolute.hasPrefix(rootPath + "/") {
                return String(absolute.dropFirst(rootPath.count + 1))
            }
            return absolute
        }()
        onOpenFile?(relativeToProject, openMode(for: entry))
    }

    private func openMode(for entry: KnowledgeFileEntry) -> FileOpenMode {
        let ext = (entry.name as NSString).pathExtension.lowercased()
        return Self.textExtensions.contains(ext) ? .edit : .preview
    }

    private static let textExtensions: Set<String> = [
        "swift", "m", "h", "c", "cpp", "rs", "go", "py", "rb", "js", "ts",
        "jsx", "tsx", "json", "yaml", "yml", "toml", "xml", "plist",
        "html", "css", "scss", "less", "sh", "bash", "zsh", "fish",
        "md", "markdown", "txt", "log", "env", "gitignore", "editorconfig",
        "lock", "resolved", "cfg", "ini", "conf", "sql", "graphql"
    ]
}

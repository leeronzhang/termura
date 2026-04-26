import Foundation

/// A file or folder entry inside the knowledge/sources/ or knowledge/log/ directories.
public struct KnowledgeFileEntry: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let relativePath: String
    public let isDirectory: Bool
    public let fileSize: Int?
    public let modifiedAt: Date?
    /// Grouping key: subdirectory name for sources (e.g. "articles"), date string for log.
    public let category: String

    public init(id: String, name: String, relativePath: String, isDirectory: Bool,
                fileSize: Int?, modifiedAt: Date?, category: String) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.isDirectory = isDirectory
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.category = category
    }
}

/// Lists files in knowledge/sources/ and knowledge/log/ directories.
public enum KnowledgeFileLister {
    /// List sources/ contents grouped by subdirectory (articles, papers, code, images, data).
    public static func listSources(in sourcesDir: URL) -> [KnowledgeFileEntry] {
        let subdirs: [URL]
        do {
            subdirs = try FileManager.default.contentsOfDirectory(
                at: sourcesDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: directory may not exist yet.
            return []
        }

        var entries: [KnowledgeFileEntry] = []
        for subdir in subdirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard isDirectory(subdir) else { continue }
            entries.append(contentsOf: listFiles(in: subdir, category: subdir.lastPathComponent, baseDir: sourcesDir))
        }
        return entries
    }

    /// List log/ contents grouped by date directory (e.g. "2026-04-26"), sorted newest first.
    public static func listLogs(in logDir: URL) -> [KnowledgeFileEntry] {
        let dateDirs: [URL]
        do {
            dateDirs = try FileManager.default.contentsOfDirectory(
                at: logDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: directory may not exist yet.
            return []
        }

        var entries: [KnowledgeFileEntry] = []
        for dateDir in dateDirs.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
            guard isDirectory(dateDir) else { continue }
            entries.append(contentsOf: listFiles(in: dateDir, category: dateDir.lastPathComponent, baseDir: logDir))
        }
        return entries
    }

    /// Flat enumeration of `directory/` (e.g. attachments/) under a single category bucket.
    /// Each entry's `relativePath` is computed against `directory` itself.
    public static func listFlat(in directory: URL, category: String) -> [KnowledgeFileEntry] {
        listFiles(in: directory, category: category, baseDir: directory)
    }

    /// Lists each immediate subdirectory of `parent` together with its files, including empty
    /// subdirectories. Sort order is alphabetical when `descending` is false, descending when true.
    /// Used to render the Knowledge sidebar's section structure even when categories are empty.
    public static func listSubdirGroups(
        in parent: URL,
        descending: Bool = false
    ) -> [(category: String, files: [KnowledgeFileEntry])] {
        let subdirs: [URL]
        do {
            subdirs = try FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: parent may not exist yet.
            return []
        }
        let sorted = subdirs.sorted { lhs, rhs in
            let lhsName = lhs.lastPathComponent
            let rhsName = rhs.lastPathComponent
            return descending ? lhsName > rhsName : lhsName < rhsName
        }
        return sorted.compactMap { subdir in
            guard isDirectory(subdir) else { return nil }
            let files = listFiles(in: subdir, category: subdir.lastPathComponent, baseDir: parent)
            return (subdir.lastPathComponent, files)
        }
    }

    // MARK: - Private

    private static func isDirectory(_ url: URL) -> Bool {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        } catch {
            return false
        }
    }

    private static func listFiles(in directory: URL, category: String, baseDir: URL) -> [KnowledgeFileEntry] {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Non-critical: subdirectory may be inaccessible.
            return []
        }

        return files
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .compactMap { url -> KnowledgeFileEntry? in
                let values: URLResourceValues
                do {
                    values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
                } catch {
                    return nil
                }
                let isDir = values.isDirectory ?? false
                // WHY: resolve symlinks on both sides to avoid /var vs /private/var mismatch
                let resolvedFile = url.resolvingSymlinksInPath().path
                let resolvedBase = baseDir.resolvingSymlinksInPath().path
                let relative = resolvedFile.replacingOccurrences(of: resolvedBase + "/", with: "")
                return KnowledgeFileEntry(
                    id: relative,
                    name: url.lastPathComponent,
                    relativePath: relative,
                    isDirectory: isDir,
                    fileSize: isDir ? nil : values.fileSize,
                    modifiedAt: values.contentModificationDate,
                    category: category
                )
            }
    }
}

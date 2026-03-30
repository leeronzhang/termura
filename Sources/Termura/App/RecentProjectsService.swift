import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "RecentProjects")

/// Lightweight JSON-file service tracking recently opened project directories.
/// Stored at `~/.termura/recent-projects.json` — the only global (non-project-scoped) file.
struct RecentProjectsService: Sendable {
    private let fileURL: URL
    private let fileManager: any FileManagerProtocol

    init(fileManager: any FileManagerProtocol = FileManager.default) {
        let home = URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
        let dir = home.appendingPathComponent(AppConfig.RecentProjects.globalDirectoryName)
        fileURL = dir.appendingPathComponent(AppConfig.RecentProjects.fileName)
        self.fileManager = fileManager
    }

    /// Testable initializer allowing injection of a custom file URL and file manager.
    init(fileURL: URL, fileManager: any FileManagerProtocol = FileManager.default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    // MARK: - Read

    func fetchRecent() -> [RecentProject] {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            logger.debug("No recent projects file at \(fileURL.path): \(error.localizedDescription)")
            return []
        }
        do {
            return try JSONDecoder().decode([RecentProject].self, from: data)
        } catch {
            logger.error("Failed to decode recent projects: \(error)")
            return []
        }
    }

    /// Returns the most recently opened project URL, if any.
    func lastOpened() -> URL? {
        guard let first = fetchRecent().first else { return nil }
        let url = URL(fileURLWithPath: first.path)
        guard fileManager.fileExists(atPath: first.path) else { return nil }
        return url
    }

    // MARK: - Write

    func addRecent(_ url: URL) {
        var list = fetchRecent().filter { $0.path != url.path }
        let entry = RecentProject(
            path: url.path,
            lastOpenedAt: Date(),
            displayName: url.lastPathComponent
        )
        list.insert(entry, at: 0)
        if list.count > AppConfig.RecentProjects.maxCount {
            list = Array(list.prefix(AppConfig.RecentProjects.maxCount))
        }
        save(list)
    }

    func removeRecent(_ url: URL) {
        save(fetchRecent().filter { $0.path != url.path })
    }

    // MARK: - Private

    private func save(_ list: [RecentProject]) {
        do {
            let dir = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(list)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save recent projects: \(error)")
        }
    }
}

// MARK: - Model

struct RecentProject: Codable, Sendable, Equatable {
    let path: String
    let lastOpenedAt: Date
    let displayName: String
}

import Foundation
import OSLog

private let watcherLogger = Logger(
    subsystem: "com.termura.app",
    category: "ProjectViewModel+DirectoryWatcher"
)

extension ProjectViewModel {
    // MARK: - Directory watcher

    /// Starts a recursive FSEventStream watcher over the project root so external
    /// file writes (CLI agent, Finder, sync clients) refresh the sidebar tree in
    /// near-real-time. Idempotent — second call is a no-op.
    ///
    /// WHY: prior to this the sidebar only refreshed on app activation + terminal
    /// chunk completion; an agent writing files while the app is foregrounded
    /// produced no UI update until the user toggled focus.
    /// OWNER: ProjectViewModel — `directoryWatcher` + `directoryWatchTask`.
    /// TEARDOWN: stopDirectoryWatcher() cancels the drain task and stops the
    /// underlying FSEventStream; called from tearDown() and via SidebarProjectContent's
    /// onDisappear path.
    /// TEST: covered by SidebarProjectContent integration test asserting tree
    /// updates after `touch <root>/new.txt`.
    func startDirectoryWatcher() {
        guard directoryWatcher == nil else { return }
        let url = URL(fileURLWithPath: projectRootPath)
        let watcher = ProjectDirectoryWatcher(projectURL: url)
        directoryWatcher = watcher
        directoryWatchTask = Task { [weak self] in
            await self?.drainDirectoryWatcherEvents(watcher)
        }
    }

    func drainDirectoryWatcherEvents(_ watcher: ProjectDirectoryWatcher) async {
        do {
            try await watcher.start()
        } catch {
            watcherLogger.warning(
                "ProjectDirectoryWatcher start failed: \(error.localizedDescription)"
            )
            return
        }
        for await _ in watcher.events() {
            if Task.isCancelled { break }
            debouncedRefresh()
        }
        await watcher.stop()
    }

    func stopDirectoryWatcher() {
        directoryWatchTask?.cancel()
        directoryWatchTask = nil
        let watcher = directoryWatcher
        directoryWatcher = nil
        if let watcher {
            Task { await watcher.stop() }
        }
    }
}

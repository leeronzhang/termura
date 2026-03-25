import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectViewModel")

/// Drives the Project sidebar tab: file tree + git status + badge.
@MainActor
final class ProjectViewModel: ObservableObject {
    @Published private(set) var tree: [FileTreeNode] = []
    @Published private(set) var gitResult: GitStatusResult = .notARepo
    @Published private(set) var isLoading = false
    /// IDs of expanded folder nodes. Root-level folders are auto-expanded on first scan.
    @Published var expandedNodeIDs: Set<String> = []

    /// True when there are uncommitted changes — drives the tab badge dot.
    var hasUncommittedChanges: Bool { !gitResult.files.isEmpty }

    /// Full project root for tooltip.
    var projectRootPath: String { projectRoot }

    /// Shortened display path: replaces home directory with `~`.
    var displayPath: String {
        let home = AppConfig.Paths.homeDirectory
        if projectRoot.hasPrefix(home) {
            return "~" + projectRoot.dropFirst(home.count)
        }
        return projectRoot
    }

    private let gitService: any GitServiceProtocol
    private let fileTreeService = FileTreeService()
    private let projectRoot: String
    private weak var commandRouter: CommandRouter?
    private var refreshTask: Task<Void, Never>?
    private var appActiveObserver: (any NSObjectProtocol)?
    private var debounceTask: Task<Void, Never>?

    init(
        gitService: any GitServiceProtocol,
        projectRoot: String,
        commandRouter: CommandRouter? = nil
    ) {
        self.gitService = gitService
        self.projectRoot = projectRoot
        self.commandRouter = commandRouter
        setupObservers()
    }

    func tearDown() {
        if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        appActiveObserver = nil
        refreshTask?.cancel()
        debounceTask?.cancel()
    }

    // MARK: - Public

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task { [weak self] in
            guard let self else { return }

            // Scan file tree and git status in parallel
            async let scannedTree = fileTreeService.scan(at: projectRoot)
            async let gitStatus = {
                do {
                    return try await self.gitService.status(at: self.projectRoot)
                } catch {
                    logger.warning("Git status failed: \(error.localizedDescription)")
                    return GitStatusResult.notARepo
                }
            }()

            let rawTree = await scannedTree
            let status = await gitStatus
            guard !Task.isCancelled else { return }

            // Annotate tree with git status
            let annotated = await fileTreeService.annotate(tree: rawTree, with: status)
            guard !Task.isCancelled else { return }

            tree = annotated
            gitResult = status
            isLoading = false

            // Auto-expand root directories on first scan
            if expandedNodeIDs.isEmpty {
                for node in annotated where node.isDirectory {
                    expandedNodeIDs.insert(node.id)
                }
            }

            commandRouter?.hasUncommittedChanges = !status.files.isEmpty
        }
    }

    // MARK: - Private

    private func setupObservers() {
        // Refresh git status when a terminal chunk completes (command may have changed files).
        commandRouter?.onChunkCompleted { [weak self] _ in
            self?.debouncedRefresh()
        }

        // Refresh when the app becomes active (user may have edited files externally).
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func debouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(AppConfig.Git.refreshDebounceSeconds * 1_000_000_000)
                )
            } catch is CancellationError {
                return
            } catch {
                logger.warning("Git refresh debounce sleep failed: \(error.localizedDescription)")
                return
            }
            self?.refresh()
        }
    }
}

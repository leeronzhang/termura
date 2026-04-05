import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectViewModel")

/// Drives the Project sidebar tab: file tree + git status + badge.
@Observable
@MainActor
final class ProjectViewModel {
    private(set) var tree: [FileTreeNode] = [] {
        didSet { treeManager.updateTree(tree) }
    }

    private(set) var gitResult: GitStatusResult = .notARepo
    private(set) var isLoading = false
    /// User-visible error from the last refresh; nil when healthy.
    var errorMessage: String?

    /// IDs of expanded folder nodes. Persisted per project via UserDefaults.
    var expandedNodeIDs: Set<String> {
        get { treeManager.expandedNodeIDs }
        set {
            treeManager.setExpandedNodeIDs(newValue)
            persistExpandedIDs()
        }
    }

    /// When true, files/directories marked as gitignored are hidden from the tree.
    var hideIgnoredFiles: Bool {
        get { treeManager.hideIgnoredFiles }
        set {
            treeManager.setHideIgnoredFiles(newValue)
            userDefaults.set(newValue, forKey: hideIgnoredKey)
        }
    }

    /// Cached flat list of visible tree items (proxied from treeManager).
    var flatVisibleItems: [FlatTreeItem] { treeManager.flatVisibleItems }

    var hasUncommittedChanges: Bool { !gitResult.files.isEmpty } // drives tab badge dot
    var projectRootPath: String { projectRoot }
    /// Shortened display path: replaces home directory with `~`.
    var displayPath: String {
        let home = AppConfig.Paths.homeDirectory
        return projectRoot.hasPrefix(home) ? "~" + projectRoot.dropFirst(home.count) : projectRoot
    }

    private let gitService: any GitServiceProtocol
    private let clock: any AppClock
    private let fileTreeService: any FileTreeServiceProtocol
    private let projectRoot: String
    private let userDefaults: any UserDefaultsStoring
    private let treeManager: FileTreeManager
    private var commandRouter: CommandRouter?
    private var chunkHandlerToken: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var appActiveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    private var hasRestoredExpandState = false

    init(
        gitService: any GitServiceProtocol,
        projectRoot: String,
        commandRouter: CommandRouter? = nil,
        fileTreeService: any FileTreeServiceProtocol = FileTreeService(),
        clock: any AppClock = LiveClock(),
        userDefaults: any UserDefaultsStoring = UserDefaults.standard
    ) {
        self.gitService = gitService
        self.projectRoot = projectRoot
        self.commandRouter = commandRouter
        self.fileTreeService = fileTreeService
        self.clock = clock
        self.userDefaults = userDefaults
        treeManager = FileTreeManager(expandedNodeIDs: [], hideIgnoredFiles: true)
        restoreExpandedIDs()
        setupObservers()
    }

    deinit {
        refreshTask?.cancel()
        debounceTask?.cancel()
        persistTask?.cancel()
    }

    func tearDown() {
        if let observer = appActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        appActiveObserver = nil
        if let token = chunkHandlerToken {
            commandRouter?.removeChunkHandler(token: token)
            chunkHandlerToken = nil
        }
        refreshTask?.cancel()
        debounceTask?.cancel()
        persistTask?.cancel()
        userDefaults.set(Array(expandedNodeIDs), forKey: expandedIDsKey)
    }

    // MARK: - Public

    /// Toggle expand/collapse.
    func toggleExpand(_ node: FileTreeNode) {
        treeManager.toggleExpand(node)
        persistExpandedIDs()
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            // Establish a trace context so GitService OSSignposter intervals in Instruments
            // are labelled with the project root, enabling per-project latency correlation.
            // TaskLocal.withValue inherits @MainActor isolation via #isolation.
            let trace = TraceContext(spanName: "project.refresh[\(projectRoot)]")
            await TraceLocal.$current.withValue(trace) {
                await self.performRefresh()
            }
        }
    }

    private func performRefresh() async {
        // File tree scan is skipped off the project tab — expensive (contentsOfDirectory,
        // maxDepth=10), only needed for the tree view. Git status always refreshes (badge dot).
        let shouldScanTree = commandRouter?.selectedSidebarTab == .project
        let data = await fetchProjectData(shouldScanTree: shouldScanTree)
        guard !Task.isCancelled else { return }
        // Only update the tree when we actually scanned — preserves existing tree on other tabs.
        if shouldScanTree {
            let annotated = await fileTreeService.annotate(
                tree: data.rawTree, with: data.status, trackedFiles: data.trackedFiles
            )
            guard !Task.isCancelled else { return }
            // Auto-expand roots on first scan.
            if treeManager.expandedNodeIDs.isEmpty && !hasRestoredExpandState {
                hasRestoredExpandState = true
                treeManager.setExpandedNodeIDs(Set(annotated.lazy.filter(\.isDirectory).map(\.id)))
            }
            tree = annotated // tree.didSet → treeManager.updateTree()
        }

        gitResult = data.status
        isLoading = false
        // Only clear errorMessage when git actually succeeded (status has repo data).
        // fetchGitStatus sets errorMessage on infrastructure failure; clearing it here
        // would hide infra errors from the user.
        if data.status.isGitRepo {
            errorMessage = nil
        }
        commandRouter?.hasUncommittedChanges = !data.status.files.isEmpty
    }

    private struct ProjectRefreshData {
        let status: GitStatusResult
        let trackedFiles: Set<String>
        let rawTree: [FileTreeNode]
    }

    private func fetchProjectData(shouldScanTree: Bool) async -> ProjectRefreshData {
        async let statusFuture = fetchGitStatus()
        async let trackedFuture = fetchTrackedFiles()
        async let treeFuture = fetchFileTree(shouldScan: shouldScanTree)
        return await ProjectRefreshData(
            status: statusFuture,
            trackedFiles: trackedFuture,
            rawTree: treeFuture
        )
    }

    private func fetchGitStatus() async -> GitStatusResult {
        do {
            return try await gitService.status(at: projectRoot)
        } catch {
            // GitService.status already maps exit-128 to .notARepo and returns it
            // (no throw). Any error reaching here is an infrastructure problem
            // (timeout, launch failure, decode error, permission denied) — not "not a repo".
            logger.error("Git status infrastructure failure: \(error.localizedDescription)")
            errorMessage = "Git: \(error.localizedDescription)"
            return .notARepo
        }
    }

    private func fetchTrackedFiles() async -> Set<String> {
        do {
            return try await gitService.trackedFiles(at: projectRoot)
        } catch let gitError as GitServiceError {
            if case .notARepo = gitError {
                // Non-critical: not a git repo means no tracked files, expected state.
                return []
            }
            logger.error("Tracked files infrastructure failure: \(gitError.localizedDescription)")
            return []
        } catch {
            logger.error("Tracked files unexpected error: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchFileTree(shouldScan: Bool) async -> [FileTreeNode] {
        guard shouldScan else { return [] }
        return await fileTreeService.scan(at: projectRoot)
    }

    // MARK: - Private

    private func setupObservers() {
        // Refresh git status when a terminal chunk completes (command may have changed files).
        chunkHandlerToken = commandRouter?.onChunkCompleted { [weak self] _ in
            self?.debouncedRefresh()
        }

        // Refresh when the app becomes active (user may have edited files externally).
        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main // Sync body — .main + assumeIsolated avoids a Task allocation.
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    // MARK: - Expansion Persistence

    private var expandedIDsKey: String {
        AppConfig.UserDefaultsKeys.fileTreeExpandedIDs(projectRoot: projectRoot)
    }

    private var hideIgnoredKey: String {
        AppConfig.UserDefaultsKeys.fileTreeHideIgnored(projectRoot: projectRoot)
    }

    private func persistExpandedIDs() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.UI.expansionPersistDebounce)
            } catch is CancellationError {
                // CancellationError is expected — a newer expansion event supersedes this persist.
                return
            } catch {
                logger.debug("Expansion persist debounce interrupted: \(error.localizedDescription)")
                return
            }
            guard let self, !Task.isCancelled else { return }
            userDefaults.set(Array(expandedNodeIDs), forKey: expandedIDsKey)
        }
    }

    private func restoreExpandedIDs() {
        if let saved = userDefaults.stringArray(forKey: expandedIDsKey) {
            treeManager.setExpandedNodeIDs(Set(saved))
            hasRestoredExpandState = !saved.isEmpty
        }
        // Restore ignore filter (defaults to true if not set)
        if userDefaults.object(forKey: hideIgnoredKey) != nil {
            treeManager.setHideIgnoredFiles(userDefaults.bool(forKey: hideIgnoredKey))
        }
    }

    private func debouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            do {
                try await self?.clock.sleep(for: AppConfig.Git.refreshDebounce)
            } catch is CancellationError {
                // CancellationError is expected — a newer refresh event supersedes this one.
                return
            } catch {
                logger.warning("Git refresh debounce interrupted: \(error.localizedDescription)")
                return
            }
            self?.refresh()
        }
    }
}

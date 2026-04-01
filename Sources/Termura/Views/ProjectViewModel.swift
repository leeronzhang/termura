import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectViewModel")

/// Drives the Project sidebar tab: file tree + git status + badge.
@Observable
@MainActor
final class ProjectViewModel {
    private(set) var tree: [FileTreeNode] = [] {
        didSet { rebuildFlatVisibleItems() }
    }
    private(set) var gitResult: GitStatusResult = .notARepo
    private(set) var isLoading = false
    /// User-visible error from the last refresh; nil when healthy.
    var errorMessage: String?
    /// IDs of expanded folder nodes. Persisted per project via UserDefaults.
    var expandedNodeIDs: Set<String> = [] {
        // No rebuild: toggleExpand splices incrementally; batch sets precede tree.didSet.
        didSet { persistExpandedIDs() }
    }

    /// When true, files/directories marked as gitignored are hidden from the tree.
    var hideIgnoredFiles: Bool = true {
        didSet {
            userDefaults.set(hideIgnoredFiles, forKey: hideIgnoredKey)
            if _unfilteredDirty {
                rebuildFlatVisibleItems()
            } else {
                applyIgnoreFilter()
            }
        }
    }

    /// Cached flat list of visible tree items (rebuilt on tree/expansion/filter changes).
    private(set) var flatVisibleItems: [FlatTreeItem] = []

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
    private var commandRouter: CommandRouter?
    private var chunkHandlerToken: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var appActiveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    private var hasRestoredExpandState = false // true after first expand-state restore
    @ObservationIgnored private var _unfilteredFlatItems: [FlatTreeItem] = [] // cached unfiltered list
    @ObservationIgnored private var _unfilteredDirty = true // marked dirty by toggleExpand

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

    /// Toggle expand/collapse. Incremental splice: O(items affected) vs O(all visible).
    func toggleExpand(_ node: FileTreeNode) {
        guard node.isDirectory else { return }
        _unfilteredDirty = true
        if expandedNodeIDs.contains(node.id) {
            expandedNodeIDs.remove(node.id)
            removeVisibleDescendants(of: node)
        } else {
            expandedNodeIDs.insert(node.id)
            insertVisibleChildren(of: node)
        }
    }

    func refresh() {
        refreshTask?.cancel()
        isLoading = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            // Establish a trace context so GitService OSSignposter intervals in Instruments
            // are labelled with the project root, enabling per-project latency correlation.
            // TaskLocal.withValue inherits @MainActor isolation via #isolation.
            let trace = TraceContext(spanName: "project.refresh[\(self.projectRoot)]")
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
            // Auto-expand roots on first scan. Set expandedNodeIDs BEFORE tree so tree.didSet
            // fires once with the correct expansion state (expandedNodeIDs.didSet only persists).
            if expandedNodeIDs.isEmpty && !hasRestoredExpandState {
                hasRestoredExpandState = true
                expandedNodeIDs = Set(annotated.lazy.filter(\.isDirectory).map(\.id))
            }
            tree = annotated      // tree.didSet → rebuildFlatVisibleItems() with correct IDs
        }

        gitResult = data.status
        isLoading = false
        errorMessage = nil
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
        return ProjectRefreshData(
            status: await statusFuture,
            trackedFiles: await trackedFuture,
            rawTree: await treeFuture
        )
    }
    private func fetchGitStatus() async -> GitStatusResult {
        do { return try await gitService.status(at: projectRoot) } catch {
            logger.warning("Git status failed: \(error.localizedDescription)")
            return .notARepo
        }
    }
    private func fetchTrackedFiles() async -> Set<String> {
        do { return try await gitService.trackedFiles(at: projectRoot) } catch {
            logger.warning("Tracked files fetch failed: \(error.localizedDescription)")
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
            queue: .main  // Sync body — .main + assumeIsolated avoids a Task allocation.
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
            expandedNodeIDs = Set(saved)
            hasRestoredExpandState = !saved.isEmpty
        }
        // Restore ignore filter (defaults to true if not set)
        if userDefaults.object(forKey: hideIgnoredKey) != nil {
            hideIgnoredFiles = userDefaults.bool(forKey: hideIgnoredKey)
        }
    }

    private func rebuildFlatVisibleItems() {
        _unfilteredFlatItems = tree.flattenVisible(expandedIDs: expandedNodeIDs)
        _unfilteredDirty = false
        applyIgnoreFilter()
    }

    private func applyIgnoreFilter() { // O(n) filter, no tree traversal
        flatVisibleItems = hideIgnoredFiles ? _unfilteredFlatItems.filter { !$0.node.isGitIgnored } : _unfilteredFlatItems
    }

    // MARK: - Incremental flat-list mutations (expand/collapse hot path)

    /// O(inserted items + elements shifted after insertion point).
    private func insertVisibleChildren(of node: FileTreeNode) {
        guard let idx = flatVisibleItems.firstIndex(where: { $0.id == node.id }),
              let children = node.children else { return }
        var toInsert: [FlatTreeItem] = []
        appendVisibleNodes(children, depth: flatVisibleItems[idx].depth + 1, into: &toInsert)
        guard !toInsert.isEmpty else { return }
        flatVisibleItems.insert(contentsOf: toInsert, at: idx + 1)
    }
    private func removeVisibleDescendants(of node: FileTreeNode) { // O(removed + shifted elements)
        guard let idx = flatVisibleItems.firstIndex(where: { $0.id == node.id }) else { return }
        let depth = flatVisibleItems[idx].depth
        let start = idx + 1
        var end = start
        while end < flatVisibleItems.count && flatVisibleItems[end].depth > depth { end += 1 }
        guard end > start else { return }
        flatVisibleItems.removeSubrange(start..<end)
    }
    /// Recursively builds the flat list for `nodes` honouring expansion and ignore filter.
    private func appendVisibleNodes(_ nodes: [FileTreeNode], depth: Int, into result: inout [FlatTreeItem]) {
        for node in nodes {
            if hideIgnoredFiles && node.isGitIgnored { continue }
            result.append(FlatTreeItem(node: node, depth: depth))
            if node.isDirectory, expandedNodeIDs.contains(node.id), let children = node.children {
                appendVisibleNodes(children, depth: depth + 1, into: &result)
            }
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

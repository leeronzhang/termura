import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectViewModel")

/// Drives the Project sidebar tab: file tree + git status + badge.
@Observable
@MainActor
final class ProjectViewModel {
    private(set) var tree: [FileTreeNode] = []
    private(set) var gitResult: GitStatusResult = .notARepo
    private(set) var isLoading = false
    /// User-visible error from the last refresh; nil when healthy.
    var errorMessage: String?
    /// IDs of expanded folder nodes. Persisted per project via UserDefaults.
    var expandedNodeIDs: Set<String> = [] {
        didSet { persistExpandedIDs() }
    }

    /// When true, files/directories marked as gitignored are hidden from the tree.
    var hideIgnoredFiles: Bool = true {
        didSet { UserDefaults.standard.set(hideIgnoredFiles, forKey: hideIgnoredKey) }
    }

    /// Flattened list of visible tree items based on expansion and ignore filter.
    var flatVisibleItems: [FlatTreeItem] {
        let items = tree.flattenVisible(expandedIDs: expandedNodeIDs)
        guard hideIgnoredFiles else { return items }
        return items.filter { !$0.node.isGitIgnored }
    }

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
    private let clock: any AppClock
    private let fileTreeService: any FileTreeServiceProtocol
    private let projectRoot: String
    private var commandRouter: CommandRouter?
    private var chunkHandlerToken: UUID?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var appActiveObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var persistTask: Task<Void, Never>?
    /// Tracks whether we've already handled initial expansion (persisted or auto).
    private var hasRestoredExpandState = false

    init(
        gitService: any GitServiceProtocol,
        projectRoot: String,
        commandRouter: CommandRouter? = nil,
        fileTreeService: any FileTreeServiceProtocol = FileTreeService(),
        clock: any AppClock = LiveClock()
    ) {
        self.gitService = gitService
        self.projectRoot = projectRoot
        self.commandRouter = commandRouter
        self.fileTreeService = fileTreeService
        self.clock = clock
        restoreExpandedIDs()
        setupObservers()
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
        // Flush expansion state immediately on teardown
        let array = Array(expandedNodeIDs)
        UserDefaults.standard.set(array, forKey: expandedIDsKey)
    }

    // MARK: - Public

    /// Toggle the expand/collapse state of a directory node.
    func toggleExpand(_ node: FileTreeNode) {
        guard node.isDirectory else { return }
        if expandedNodeIDs.contains(node.id) {
            expandedNodeIDs.remove(node.id)
        } else {
            expandedNodeIDs.insert(node.id)
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
        // Scan file tree, git status, and tracked files in parallel
        async let scannedTree = fileTreeService.scan(at: projectRoot)
        async let gitStatus = {
            do {
                return try await self.gitService.status(at: self.projectRoot)
            } catch {
                // Non-critical: git status is optional — project tree still works without it.
                logger.warning("Git status failed: \(error.localizedDescription)")
                return GitStatusResult.notARepo
            }
        }()
        async let tracked = {
            do {
                return try await self.gitService.trackedFiles(at: self.projectRoot)
            } catch {
                // Non-critical: tracked files are optional — tree shows all files as fallback.
                logger.warning("Tracked files fetch failed: \(error.localizedDescription)")
                return Set<String>()
            }
        }()

        let rawTree = await scannedTree
        let status = await gitStatus
        let trackedFiles = await tracked
        guard !Task.isCancelled else { return }

        // Annotate tree with git status and ignored file detection
        let annotated = await fileTreeService.annotate(
            tree: rawTree, with: status, trackedFiles: trackedFiles
        )
        guard !Task.isCancelled else { return }

        tree = annotated
        gitResult = status
        isLoading = false
        errorMessage = nil

        // Auto-expand root directories only on very first scan (no persisted state)
        if expandedNodeIDs.isEmpty && !hasRestoredExpandState {
            hasRestoredExpandState = true
            for node in annotated where node.isDirectory {
                expandedNodeIDs.insert(node.id)
            }
        }

        commandRouter?.hasUncommittedChanges = !status.files.isEmpty
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
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
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
                // Non-critical: expansion state is cosmetic; lost state is auto-restored on next scan.
                logger.debug("Expansion persist debounce interrupted: \(error.localizedDescription)")
                return
            }
            guard let self, !Task.isCancelled else { return }
            let array = Array(expandedNodeIDs)
            UserDefaults.standard.set(array, forKey: expandedIDsKey)
        }
    }

    private func restoreExpandedIDs() {
        if let saved = UserDefaults.standard.stringArray(forKey: expandedIDsKey) {
            expandedNodeIDs = Set(saved)
            hasRestoredExpandState = !saved.isEmpty
        }
        // Restore ignore filter (defaults to true if not set)
        if UserDefaults.standard.object(forKey: hideIgnoredKey) != nil {
            hideIgnoredFiles = UserDefaults.standard.bool(forKey: hideIgnoredKey)
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
                // Non-critical: git refresh is a background heuristic; the tree remains usable.
                logger.warning("Git refresh debounce sleep failed: \(error.localizedDescription)")
                return
            }
            self?.refresh()
        }
    }
}

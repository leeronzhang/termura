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

    /// True when there are uncommitted changes — drives the tab badge dot.
    var hasUncommittedChanges: Bool { !gitResult.files.isEmpty }

    private let gitService: any GitServiceProtocol
    private let fileTreeService = FileTreeService()
    private let projectRoot: String
    private var refreshTask: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []
    private var debounceTask: Task<Void, Never>?

    init(gitService: any GitServiceProtocol, projectRoot: String) {
        self.gitService = gitService
        self.projectRoot = projectRoot
        setupObservers()
    }

    func tearDown() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
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

            NotificationCenter.default.post(
                name: .projectGitStatusChanged,
                object: !status.files.isEmpty
            )
        }
    }

    // MARK: - Private

    private func setupObservers() {
        let chunkObs = NotificationCenter.default.addObserver(
            forName: .chunkCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.debouncedRefresh()
            }
        }
        observers.append(chunkObs)

        let activeObs = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        observers.append(activeObs)
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
                return
            }
            self?.refresh()
        }
    }
}

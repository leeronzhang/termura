import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "ProjectDirectoryWatcher")

/// Recursive file-system watcher for the Project sidebar. Wraps a single
/// `FSEventStream` over the project root so external writes (CLI agent /
/// Finder / sync clients) refresh the sidebar tree without requiring app
/// activation or terminal chunk completion.
///
/// **Why FSEventStream and not DispatchSource?** `DispatchSource.makeFileSystemObjectSource`
/// only fires on events against the watched directory itself; changes to children
/// produce no event. The project tree is recursive, so we need recursive watch.
/// FSEventStream is the macOS-native recursive watcher and consumes a single
/// kernel resource regardless of subtree size.
///
/// Path filtering happens in the C callback: any event whose path lies under
/// `AppConfig.FileTree.ignoredDirectories` (`.git/`, `.termura/`, `node_modules/`,
/// `.build/`, …) is dropped so a single `git commit` doesn't trigger a burst of
/// refreshes from `.git/index` writes. If at least one event survives the filter,
/// the actor schedules a debounced "changed" yield on the AsyncStream.
actor ProjectDirectoryWatcher {
    nonisolated let projectURL: URL
    private let debounce: Duration
    nonisolated let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let watchQueue = DispatchQueue(label: "com.termura.projectWatcher", qos: .utility)

    /// Stored on the actor so the C callback can read it through the actor pointer.
    /// Project-root-relative path prefixes that, when matched, cause an event to be ignored.
    nonisolated let ignoredPrefixes: [String]
    /// Whether to additionally skip events whose first relative path segment starts with `.`.
    nonisolated let ignoreDotfiles: Bool

    private var fsStream: FSEventStreamRef?
    /// Token for the in-flight debounce — replaced on every surviving event so
    /// only the last event in a burst triggers a yield.
    private var pendingDebounce: Task<Void, Never>?

    init(
        projectURL: URL,
        debounce: Duration = AppConfig.Notes.fileWatchDebounce,
        ignoredDirectories: Set<String> = AppConfig.FileTree.ignoredDirectories,
        ignoreDotfiles: Bool = AppConfig.FileTree.ignoredDotfiles
    ) {
        self.projectURL = projectURL
        self.debounce = debounce
        // Pre-compute absolute prefixes so the C callback path-match is a single hasPrefix.
        let rootPath = projectURL.standardizedFileURL.path
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        ignoredPrefixes = ignoredDirectories.map { "\(normalizedRoot)/\($0)" }
        self.ignoreDotfiles = ignoreDotfiles
        // WHY: bridges FSEventStream callbacks into an async consumer; .bufferingNewest(1)
        // collapses bursts so a slow consumer doesn't queue up redundant refresh ticks.
        // OWNER: ProjectDirectoryWatcher actor; continuation is finished in stop().
        // TEARDOWN: stop() invalidates the FSEventStream and finishes the continuation.
        // TEST: ProjectDirectoryWatcher integration test covers create → debounce → yield.
        let (stream, continuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        self.stream = stream
        self.continuation = continuation
    }

    nonisolated func events() -> AsyncStream<Void> { stream }

    /// Begins watching the project root recursively. Idempotent — second call is a no-op.
    func start() throws {
        guard fsStream == nil else { return }
        let path = projectURL.path
        if !FileManager.default.fileExists(atPath: path) {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        }
        let paths = [path] as CFArray

        let context = Unmanaged.passUnretained(self).toOpaque()
        var streamContext = FSEventStreamContext(
            version: 0,
            info: context,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &streamContext,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            // Latency in seconds — coarse; the debouncer narrows further.
            0.3,
            // UseCFTypes is REQUIRED: without it, the callback's `eventPaths` is a C
            // `char **` array, but we read it as CFArrayRef below. Mismatched parse
            // dereferences a non-CF pointer and crashes (use-after-cast).
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagUseCFTypes
                    | kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
            )
        ) else {
            logger.error("FSEventStreamCreate returned nil for \(path, privacy: .public)")
            throw ProjectDirectoryWatcherError.streamCreationFailed(path: path)
        }
        FSEventStreamSetDispatchQueue(created, watchQueue)
        FSEventStreamStart(created)
        fsStream = created
        logger.debug("Watching project root recursively: \(path, privacy: .public)")
    }

    /// Invalidates the FSEventStream and releases kernel resources. Safe to call multiple times.
    func stop() {
        pendingDebounce?.cancel()
        pendingDebounce = nil
        if let fsStream {
            FSEventStreamStop(fsStream)
            FSEventStreamInvalidate(fsStream)
            FSEventStreamRelease(fsStream)
            self.fsStream = nil
        }
        continuation.finish()
        logger.debug("Stopped watching project root")
    }

    // MARK: - Event handling

    /// Called by the C callback with the surviving (non-filtered) event count.
    /// Hops back onto actor isolation to schedule the debounced yield.
    private nonisolated func handleEventBurst() {
        Task { await self.scheduleYield() }
    }

    private func scheduleYield() {
        pendingDebounce?.cancel()
        let debounce = debounce
        let continuation = continuation
        // WHY: collapses a burst of FSEvent callbacks (Finder copy of N files = N events)
        // into a single refresh tick; newer events supersede the in-flight wait.
        // OWNER: ProjectDirectoryWatcher actor — stored in `self.pendingDebounce`.
        // TEARDOWN: self-completing — one Task.sleep + one continuation.yield, no loop.
        // stop() cancels the in-flight task and clears the slot.
        // TEST: ProjectDirectoryWatcher integration test asserts a 5-file burst yields once.
        pendingDebounce = Task { [weak self] in
            await self?.runDebouncedYield(debounce: debounce, continuation: continuation)
        }
    }

    private func runDebouncedYield(debounce: Duration,
                                   continuation: AsyncStream<Void>.Continuation) async {
        do {
            try await Task.sleep(for: debounce)
        } catch is CancellationError {
            // CancellationError is expected — newer event superseded this debounce, or stop() cancelled the task.
            return
        } catch {
            logger.debug("Project watcher debounce interrupted: \(error.localizedDescription)")
            return
        }
        guard !Task.isCancelled else { return }
        continuation.yield(())
        pendingDebounce = nil
    }

    // MARK: - Filtering (called from the C callback, nonisolated)

    /// Returns true if at least one of `paths` is not under an ignored prefix.
    /// Run on the FSEventStream callback queue — must be nonisolated.
    nonisolated func anyRelevantPath(_ paths: [String]) -> Bool {
        let rootPath = projectURL.standardizedFileURL.path
        let normalizedRoot = rootPath.hasSuffix("/") ? String(rootPath.dropLast()) : rootPath
        let rootPrefixLen = normalizedRoot.count + 1 // include trailing '/'
        for path in paths {
            if isIgnored(absolutePath: path, rootPrefixLen: rootPrefixLen) { continue }
            return true
        }
        return false
    }

    private nonisolated func isIgnored(absolutePath: String, rootPrefixLen: Int) -> Bool {
        for prefix in ignoredPrefixes {
            if absolutePath == prefix || absolutePath.hasPrefix(prefix + "/") {
                return true
            }
        }
        guard ignoreDotfiles else { return false }
        // Skip events whose first project-relative segment begins with `.`.
        if absolutePath.count > rootPrefixLen {
            let relStart = absolutePath.index(absolutePath.startIndex, offsetBy: rootPrefixLen)
            let relative = absolutePath[relStart...]
            if let firstSegment = relative.split(separator: "/", maxSplits: 1).first,
               firstSegment.hasPrefix(".") {
                return true
            }
        }
        return false
    }

    // MARK: - C callback bridge

    private static let callback: FSEventStreamCallback = { _, contextInfo, numEvents, eventPaths, _, _ in
        guard let contextInfo else { return }
        let watcher = Unmanaged<ProjectDirectoryWatcher>
            .fromOpaque(contextInfo).takeUnretainedValue()
        // eventPaths is a CFArrayRef of CFStringRef when kFSEventStreamCreateFlagUseCFTypes is set
        // (default). Bridge to [String] for Swift-side filtering.
        let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
        var collected: [String] = []
        collected.reserveCapacity(numEvents)
        for index in 0 ..< numEvents {
            guard let raw = CFArrayGetValueAtIndex(cfArray, index) else { continue }
            let cfString = Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue()
            collected.append(cfString as String)
        }
        guard watcher.anyRelevantPath(collected) else { return }
        watcher.handleEventBurst()
    }
}

enum ProjectDirectoryWatcherError: Error, LocalizedError, Sendable {
    case streamCreationFailed(path: String)

    var errorDescription: String? {
        switch self {
        case let .streamCreationFailed(path):
            String(localized: "Could not start watching project directory: \(path)")
        }
    }
}

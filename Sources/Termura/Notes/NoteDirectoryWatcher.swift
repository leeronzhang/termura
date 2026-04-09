import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "NoteDirectoryWatcher")

// MARK: - Protocol

protocol NoteDirectoryWatcherProtocol: Actor {
    func events() -> AsyncStream<NoteDirectoryEvent>
    func start() throws
    func stop()
}

enum NoteDirectoryEvent: Sendable {
    case changed
}

// MARK: - Implementation

/// Watches a directory for file-system write events using DispatchSource.
/// Events are debounced and exposed as an AsyncStream.
actor NoteDirectoryWatcher: NoteDirectoryWatcherProtocol {
    private let directoryURL: URL
    private let debounce: Duration
    nonisolated let noteEvents: AsyncStream<NoteDirectoryEvent>
    private let continuation: AsyncStream<NoteDirectoryEvent>.Continuation
    /// Dedicated serial queue for DispatchSource event handling (DispatchSource requires a DispatchQueue).
    private let watchQueue = DispatchQueue(label: "com.termura.noteWatcher", qos: .utility)

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    init(directoryURL: URL, debounce: Duration = AppConfig.Notes.fileWatchDebounce) {
        self.directoryURL = directoryURL
        self.debounce = debounce
        // WHY: File watcher events must cross from DispatchSource into async consumers as a buffered stream.
        // OWNER: NoteDirectoryWatcher owns the AsyncStream continuation for its full actor lifetime.
        // TEARDOWN: stop() finishes the continuation and cancels the DispatchSource/debounce work.
        // TEST: Cover debounced change delivery and stop() shutting the stream down cleanly.
        let (stream, continuation) = AsyncStream.makeStream(
            of: NoteDirectoryEvent.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        noteEvents = stream
        self.continuation = continuation
    }

    nonisolated func events() -> AsyncStream<NoteDirectoryEvent> {
        noteEvents
    }

    func start() throws {
        guard source == nil else { return }

        let dirPath = directoryURL.path
        let openedFD = open(dirPath, O_EVTONLY)
        guard openedFD >= 0 else {
            logger.error("Failed to open directory for watching: \(dirPath)")
            throw NoteFileError.fileReadFailed(path: dirPath,
                                               underlying: POSIXError(.ENOENT))
        }
        fileDescriptor = openedFD

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: openedFD,
            eventMask: .write,
            queue: watchQueue
        )

        let capturedContinuation = continuation
        let capturedDebounce = debounce
        // nonisolated handler — only touches `let` captured values and a local Task variable.
        var localDebounceTask: Task<Void, Never>?
        src.setEventHandler {
            localDebounceTask?.cancel()
            localDebounceTask = Task {
                do {
                    try await Task.sleep(for: capturedDebounce)
                    capturedContinuation.yield(.changed)
                } catch is CancellationError {
                    logger.debug("Note watcher debounce cancelled by newer event")
                } catch {
                    logger.debug("Note watcher debounce interrupted: \(error.localizedDescription)")
                }
            }
        }

        src.setCancelHandler { [openedFD] in
            localDebounceTask?.cancel()
            close(openedFD)
        }

        source = src
        src.resume()
        let dirName = directoryURL.lastPathComponent
        logger.debug("Started watching notes directory: \(dirName)")
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
        continuation.finish()
        logger.debug("Stopped watching notes directory")
    }
}

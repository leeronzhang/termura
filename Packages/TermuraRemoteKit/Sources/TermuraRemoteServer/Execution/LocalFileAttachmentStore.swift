import CryptoKit
import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "LocalFileAttachmentStore")

/// Disk-backed `AttachmentStore` for output snapshots that exceed the inline
/// byte budget. Writes content-addressed `<sha256>.bin` files into a single
/// flat directory and prunes by LRU once the file count or total bytes exceed
/// fixed budgets.
///
/// Retention policy is intentionally hard-coded for now (200 files, 1 GiB,
/// 5-minute protection window) — these are implementation-level resource
/// limits, not a user-facing promise, and the spec deliberately keeps them
/// out of the settings surface.
///
/// OWNER: `RemoteServerHarness` constructs and shares the store
/// CANCEL: writes are atomic single-shot; in-flight writes are not
///         interruptible and finish naturally
/// TEARDOWN: drop reference; files persist for the next session
public actor LocalFileAttachmentStore: AttachmentStore {
    public struct Configuration: Sendable, Equatable {
        public let rootURL: URL
        public let maxFileCount: Int
        public let maxTotalBytes: Int
        /// Files younger than this age are protected from LRU eviction so we
        /// don't reclaim the very attachment we just wrote out before the
        /// client has had a chance to see the reference.
        public let minRetentionInterval: TimeInterval

        public init(
            rootURL: URL,
            maxFileCount: Int = 200,
            maxTotalBytes: Int = 1024 * 1024 * 1024,
            minRetentionInterval: TimeInterval = 5 * 60
        ) {
            self.rootURL = rootURL
            self.maxFileCount = maxFileCount
            self.maxTotalBytes = maxTotalBytes
            self.minRetentionInterval = minRetentionInterval
        }
    }

    private struct Entry: Sendable, Equatable {
        let identifier: String
        let byteCount: Int
        let createdAt: Date
    }

    private let configuration: Configuration
    private let clock: @Sendable () -> Date
    /// Sorted oldest first so prune iterates from the head.
    private var entries: [Entry] = []
    private var bootstrapped = false

    public init(
        configuration: Configuration,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.clock = clock
    }

    public init(rootURL: URL) {
        configuration = Configuration(rootURL: rootURL)
        clock = { Date() }
    }

    /// Creates the root directory and indexes any existing `<sha>.bin` files
    /// left from a prior session so the LRU window survives restarts.
    /// Idempotent — safe to call from `RemoteServerHarness.assembleIfNeeded`.
    public func bootstrap() throws {
        if bootstrapped { return }
        try ensureDirectoryExists()
        try loadExistingIndex()
        bootstrapped = true
    }

    public func store(_ data: Data) async throws -> SnapshotAttachmentRef {
        try ensureBootstrapped()
        let identifier = Self.sha256Hex(data)
        let fileURL = url(for: identifier)
        let now = clock()
        // Content-addressed: identical bytes resolve to the same identifier,
        // so a repeat write just refreshes the existing entry's mtime to keep
        // it on the LRU's "recently used" side.
        if entries.contains(where: { $0.identifier == identifier }),
           FileManager.default.fileExists(atPath: fileURL.path) {
            touch(identifier: identifier, at: now)
            return makeRef(identifier: identifier, byteCount: data.count, sha256Hex: identifier)
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw AttachmentError.writeFailure(reason: error.localizedDescription)
        }
        entries.append(Entry(identifier: identifier, byteCount: data.count, createdAt: now))
        prune(now: now)
        return makeRef(identifier: identifier, byteCount: data.count, sha256Hex: identifier)
    }

    /// Test / diagnostics hook returning the current index in oldest-first
    /// order. Intentionally `internal` to the package — production callers
    /// only ever observe attachments via the snapshot's `attachmentRef`.
    func indexedIdentifiers() -> [String] {
        entries.map(\.identifier)
    }

    public func totalBytes() -> Int {
        entries.reduce(0) { $0 + $1.byteCount }
    }

    public func fileCount() -> Int {
        entries.count
    }

    private func ensureBootstrapped() throws {
        if !bootstrapped {
            try bootstrap()
        }
    }

    private func ensureDirectoryExists() throws {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: configuration.rootURL.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw AttachmentError.writeFailure(
                reason: "\(configuration.rootURL.path) exists but is not a directory"
            )
        }
        do {
            try fileManager.createDirectory(at: configuration.rootURL, withIntermediateDirectories: true)
        } catch {
            throw AttachmentError.writeFailure(reason: error.localizedDescription)
        }
    }

    private func loadExistingIndex() throws {
        let fileManager = FileManager.default
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: configuration.rootURL,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            // Empty / missing dir on first launch is not actionable; index stays empty.
            entries = []
            return
        }
        var loaded: [Entry] = []
        for url in urls where url.pathExtension == "bin" {
            let identifier = url.deletingPathExtension().lastPathComponent
            guard identifier.count == 64 else { continue }
            let size: Int
            let mtime: Date
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                size = values.fileSize ?? 0
                mtime = values.contentModificationDate ?? clock()
            } catch {
                // Skip un-readable entry; pruning will remove it next pass.
                continue
            }
            loaded.append(Entry(identifier: identifier, byteCount: size, createdAt: mtime))
        }
        loaded.sort { $0.createdAt < $1.createdAt }
        entries = loaded
    }

    private func touch(identifier: String, at now: Date) {
        guard let index = entries.firstIndex(where: { $0.identifier == identifier }) else { return }
        let existing = entries.remove(at: index)
        entries.append(Entry(identifier: existing.identifier, byteCount: existing.byteCount, createdAt: now))
        let fileURL = url(for: identifier)
        do {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fileURL.path)
        } catch {
            // Non-critical: setting mtime is a hint for pruning order. The
            // in-memory entry above is authoritative.
        }
    }

    private func prune(now: Date) {
        // Iterate from the oldest entry; remove only those past the retention
        // window; stop once both budgets are satisfied. Younger entries are
        // protected even if doing so leaves us temporarily over budget — this
        // is a deliberate trade vs. evicting an attachment the client may not
        // have referenced yet.
        var totalBytes = entries.reduce(0) { $0 + $1.byteCount }
        while !entries.isEmpty {
            if entries.count <= configuration.maxFileCount,
               totalBytes <= configuration.maxTotalBytes {
                return
            }
            let candidate = entries[0]
            let age = now.timeIntervalSince(candidate.createdAt)
            if age < configuration.minRetentionInterval {
                logger.info("LRU prune skipped \(candidate.identifier) (age \(age, format: .fixed(precision: 1))s < min retention)")
                return
            }
            entries.removeFirst()
            totalBytes -= candidate.byteCount
            let fileURL = url(for: candidate.identifier)
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                continue
            } catch {
                logger.warning("LRU prune failed to remove \(candidate.identifier): \(error.localizedDescription)")
            }
        }
    }

    private func url(for identifier: String) -> URL {
        configuration.rootURL.appendingPathComponent("\(identifier).bin")
    }

    private func makeRef(identifier: String, byteCount: Int, sha256Hex: String) -> SnapshotAttachmentRef {
        SnapshotAttachmentRef(
            storage: .localFile,
            identifier: "\(identifier).bin",
            byteCount: byteCount,
            sha256Hex: sha256Hex
        )
    }

    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "AuditLogStore")

/// Append-only log of remote command outcomes. Backed by JSON on disk so the
/// user can review history across app restarts; capped to keep the file small.
///
/// OWNER: typically `RemoteServerHarness` constructs and shares the store
/// CANCEL: stores are passive — no in-flight work to cancel
/// TEARDOWN: drop reference; no resources to release
public protocol AuditLogStore: Sendable {
    /// Adds a row at the end of the log. Implementations may drop the oldest
    /// entries to honour a max-entry cap.
    func append(_ entry: RemoteAuditEntry) async

    /// Returns entries newest-first, optionally bounded by `limit`.
    func recent(limit: Int) async -> [RemoteAuditEntry]
}

public actor InMemoryAuditLogStore: AuditLogStore {
    public let maxEntries: Int
    private var entries: [RemoteAuditEntry] = []

    public init(maxEntries: Int = 500) {
        self.maxEntries = maxEntries
    }

    public func append(_ entry: RemoteAuditEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func recent(limit: Int) -> [RemoteAuditEntry] {
        Array(entries.suffix(limit).reversed())
    }
}

/// File-backed audit store. Loads on first read, writes synchronously on
/// every append (audit logs are low-frequency, so the I/O cost is negligible).
/// Atomic write: temp file + rename so a crash mid-write can't corrupt the log.
public actor FileAuditLogStore: AuditLogStore {
    public enum Error: Swift.Error, Equatable {
        case readFailure(reason: String)
        case writeFailure(reason: String)
    }

    public let fileURL: URL
    public let maxEntries: Int
    private let codec: any RemoteCodec
    private var loaded: Bool = false
    private var entries: [RemoteAuditEntry] = []

    public init(
        fileURL: URL,
        maxEntries: Int = 500,
        codec: any RemoteCodec = JSONRemoteCodec()
    ) {
        self.fileURL = fileURL
        self.maxEntries = maxEntries
        self.codec = codec
    }

    public func append(_ entry: RemoteAuditEntry) async {
        await ensureLoaded()
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        do {
            try persist()
        } catch {
            logger.error("Audit log write failed: \(error.localizedDescription)")
        }
    }

    public func recent(limit: Int) async -> [RemoteAuditEntry] {
        await ensureLoaded()
        return Array(entries.suffix(limit).reversed())
    }

    private func ensureLoaded() async {
        if loaded { return }
        loaded = true
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            entries = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            entries = try codec.decode([RemoteAuditEntry].self, from: data)
        } catch {
            logger.warning("Audit log read failed; starting empty: \(error.localizedDescription)")
            entries = []
        }
    }

    private func persist() throws {
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                throw Error.writeFailure(reason: error.localizedDescription)
            }
        }
        do {
            let data = try codec.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            throw Error.writeFailure(reason: error.localizedDescription)
        }
    }
}

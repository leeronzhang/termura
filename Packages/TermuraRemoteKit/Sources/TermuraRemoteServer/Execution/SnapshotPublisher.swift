import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.remote", category: "SnapshotPublisher")

/// Outcome of packaging a single command's stdout into a `RemoteSnapshot`.
/// The publisher never throws on attachment-store failure: callers must still
/// be able to deliver a truncated preview to the client even when the full
/// attachment can't be persisted, so the failure mode is encoded as a value.
public enum SnapshotPackResult: Sendable, Equatable {
    /// Output fit inside the inline byte budget; no attachment was written.
    case inline(RemoteSnapshot)
    /// Output exceeded the inline budget; full bytes are persisted to the
    /// attachment store and the snapshot carries a `attachmentRef`.
    case attached(RemoteSnapshot)
    /// Output exceeded the inline budget but the attachment store rejected
    /// the write. The snapshot still carries a UTF-8-safe truncated preview
    /// (`truncated == true`, `attachmentRef == nil`) so the client can display
    /// "Output truncated; full attachment unavailable" rather than seeing
    /// nothing at all.
    case attachmentUnavailable(snapshot: RemoteSnapshot, reason: String)

    public var snapshot: RemoteSnapshot {
        switch self {
        case let .inline(snap): snap
        case let .attached(snap): snap
        case let .attachmentUnavailable(snap, _): snap
        }
    }
}

public actor SnapshotPublisher {
    public struct Configuration: Sendable {
        public let inlineLimit: Int

        public init(inlineLimit: Int = SnapshotPublisher.defaultInlineLimit) {
            self.inlineLimit = inlineLimit
        }
    }

    public static let defaultInlineLimit = 256 * 1024

    private let configuration: Configuration
    private let attachmentStore: any AttachmentStore

    public init(
        configuration: Configuration = Configuration(),
        attachmentStore: any AttachmentStore
    ) {
        self.configuration = configuration
        self.attachmentStore = attachmentStore
    }

    public func collect(
        commandId: UUID,
        sessionId: UUID,
        stream: AsyncThrowingStream<CommandOutputEvent, any Error>,
        producedAt: @Sendable () -> Date = { Date() }
    ) async throws -> SnapshotPackResult {
        var buffer = ""
        var exitCode: Int32?
        for try await event in stream {
            switch event {
            case let .stdout(chunk):
                buffer.append(chunk)
            case let .finished(code):
                exitCode = code
            }
        }
        return await pack(
            commandId: commandId,
            sessionId: sessionId,
            buffer: buffer,
            exitCode: exitCode,
            producedAt: producedAt()
        )
    }

    private func pack(
        commandId: UUID,
        sessionId: UUID,
        buffer: String,
        exitCode: Int32?,
        producedAt: Date
    ) async -> SnapshotPackResult {
        let bytes = Data(buffer.utf8)
        if bytes.count <= configuration.inlineLimit {
            return .inline(RemoteSnapshot(
                commandId: commandId,
                sessionId: sessionId,
                stdout: buffer,
                attachmentRef: nil,
                exitCode: exitCode,
                truncated: false,
                producedAt: producedAt
            ))
        }
        let preview = Self.utf8SafePrefix(buffer, byteLimit: configuration.inlineLimit)
        do {
            let ref = try await attachmentStore.store(bytes)
            return .attached(RemoteSnapshot(
                commandId: commandId,
                sessionId: sessionId,
                stdout: preview,
                attachmentRef: ref,
                exitCode: exitCode,
                truncated: true,
                producedAt: producedAt
            ))
        } catch {
            // WHY: an attachment write failure must not make the whole snapshot
            // disappear — the client still benefits from the truncated preview
            // and the explicit "no ref" signal that tells its UI to show
            // "full attachment unavailable" rather than "open Mac for full".
            // OWNER: caller decides how to surface the failure (router logs,
            //        iOS UI distinguishes via `attachmentRef == nil`).
            // TEST: SnapshotPublisherTests.attachmentStoreFailureProducesUnavailableResult
            let reason = Self.failureReason(error)
            logger.warning("Attachment store failed; falling back to truncated preview: \(reason)")
            let snapshot = RemoteSnapshot(
                commandId: commandId,
                sessionId: sessionId,
                stdout: preview,
                attachmentRef: nil,
                exitCode: exitCode,
                truncated: true,
                producedAt: producedAt
            )
            return .attachmentUnavailable(snapshot: snapshot, reason: reason)
        }
    }

    /// Renders the most descriptive string we can extract from an attachment
    /// store failure. `localizedDescription` collapses our typed enum cases
    /// to a generic "operation couldn't be completed", which strips the
    /// signal we actually want to log and propagate to the client.
    static func failureReason(_ error: any Error) -> String {
        if let typed = error as? AttachmentError {
            switch typed {
            case let .storageNotConfigured(byteCount):
                return "storageNotConfigured(byteCount: \(byteCount))"
            case let .writeFailure(reason):
                return "writeFailure: \(reason)"
            }
        }
        return String(describing: error)
    }

    static func utf8SafePrefix(_ source: String, byteLimit: Int) -> String {
        var result = ""
        result.reserveCapacity(byteLimit)
        var byteCount = 0
        for character in source {
            let characterBytes = String(character).utf8.count
            if byteCount + characterBytes > byteLimit { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }
}

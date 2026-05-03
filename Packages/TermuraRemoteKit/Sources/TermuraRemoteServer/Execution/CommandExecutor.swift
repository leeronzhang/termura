import Foundation
import TermuraRemoteProtocol

public enum CommandOutputEvent: Sendable, Equatable {
    case stdout(String)
    case finished(exitCode: Int32?)
}

public protocol CommandExecutor: Sendable {
    func listSessions() async throws -> [SessionDescriptor]
    func execute(_ command: RemoteCommand) -> AsyncThrowingStream<CommandOutputEvent, any Error>
    func cancel(commandId: UUID) async
}

public protocol AttachmentStore: Sendable {
    func store(_ data: Data) async throws -> SnapshotAttachmentRef
}

public enum ExecutorError: Error, Sendable, Equatable {
    case sessionNotFound(UUID)
    case commandRejected(reason: String)
    case backendUnavailable
}

extension ExecutorError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .sessionNotFound(id):
            "No session with id \(id.uuidString)."
        case let .commandRejected(reason):
            "Command rejected: \(reason)"
        case .backendUnavailable:
            "Command executor backend is unavailable."
        }
    }
}

public struct NullAttachmentStore: AttachmentStore {
    public init() {}

    public func store(_ data: Data) async throws -> SnapshotAttachmentRef {
        throw AttachmentError.storageNotConfigured(byteCount: data.count)
    }
}

public enum AttachmentError: Error, Sendable, Equatable {
    case storageNotConfigured(byteCount: Int)
    case writeFailure(reason: String)
}

extension AttachmentError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .storageNotConfigured(byteCount):
            "Attachment storage not configured (\(byteCount)-byte payload dropped)."
        case let .writeFailure(reason):
            "Attachment write failed: \(reason)"
        }
    }
}

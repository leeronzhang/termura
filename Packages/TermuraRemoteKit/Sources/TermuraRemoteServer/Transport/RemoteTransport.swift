import Foundation
import TermuraRemoteProtocol

public protocol RemoteTransport: Sendable {
    var name: String { get }
    func start(handler: any EnvelopeHandler) async throws
    func stop() async
}

public protocol EnvelopeHandler: Sendable {
    func handle(envelope: Envelope, replyChannel: any ReplyChannel) async
    func connectionClosed(channelId: UUID) async
}

public protocol ReplyChannel: Sendable {
    var channelId: UUID { get }
    func send(_ envelope: Envelope) async throws
    func close() async
}

public enum TransportError: Error, Sendable, Equatable {
    case alreadyRunning
    case notRunning
    case bindFailure(reason: String)
    case sendFailure(reason: String)
    case decodeFailure(reason: String)
}

extension TransportError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            "Transport is already running."
        case .notRunning:
            "Transport is not running."
        case let .bindFailure(reason):
            "Transport bind failed: \(reason)"
        case let .sendFailure(reason):
            "Transport send failed: \(reason)"
        case let .decodeFailure(reason):
            "Transport decode failed: \(reason)"
        }
    }
}

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

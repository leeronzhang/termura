import Foundation
import TermuraRemoteProtocol

public protocol ClientTransport: Sendable {
    func connect() async throws
    func send(_ envelope: Envelope) async throws
    func receive() async throws -> Envelope
    func disconnect() async
}

public enum ClientTransportError: Error, Sendable, Equatable {
    case notConnected
    case connectFailure(reason: String)
    case sendFailure(reason: String)
    case receiveFailure(reason: String)
    case decodeFailure(reason: String)
}

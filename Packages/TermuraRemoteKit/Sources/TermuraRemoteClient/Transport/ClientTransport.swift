import Foundation
import TermuraRemoteProtocol

public protocol ClientTransport: Sendable {
    func connect() async throws
    func send(_ envelope: Envelope) async throws
    func receive() async throws -> Envelope
    func disconnect() async
}

public enum ClientTransportError: Error, Sendable, Equatable, LocalizedError {
    case notConnected
    case connectFailure(reason: String)
    case sendFailure(reason: String)
    case receiveFailure(reason: String)
    case decodeFailure(reason: String)

    /// Surface the associated `reason` to UI / log lines. Without this, Swift
    /// bridges enum errors through NSError with a nil description, so call
    /// sites doing `error.localizedDescription` see "The operation couldn't
    /// be completed. (TermuraRemoteClient.ClientTransportError error N.)"
    /// — the underlying NWError reason ("PolicyDenied", "Connection refused",
    /// "No route to host", etc.) is dropped, leaving the user with no
    /// actionable hint about why pair failed at the transport layer.
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            "Transport is not connected."
        case let .connectFailure(reason):
            "Connect failed: \(reason)"
        case let .sendFailure(reason):
            "Send failed: \(reason)"
        case let .receiveFailure(reason):
            "Receive failed: \(reason)"
        case let .decodeFailure(reason):
            "Decode failed: \(reason)"
        }
    }
}

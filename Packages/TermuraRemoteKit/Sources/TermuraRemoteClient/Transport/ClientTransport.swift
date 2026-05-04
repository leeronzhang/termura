import Foundation
import TermuraRemoteProtocol

public protocol ClientTransport: Sendable {
    /// Emits transport-health transitions so the store-side reconnect
    /// controller can drive automatic recovery without polling.
    /// Conformers that have no health signal (e.g. `CloudKitClientTransport`,
    /// which already retries internally via `CKDatabaseOperation`) inherit
    /// the protocol-extension default that immediately finishes — the
    /// `for await` loop on the consumer side falls through and the
    /// store treats the transport as healthy until a thrown error says
    /// otherwise.
    nonisolated var events: AsyncStream<TransportEvent> { get }
    func connect() async throws
    func send(_ envelope: Envelope) async throws
    func receive() async throws -> Envelope
    func disconnect() async
}

public extension ClientTransport {
    nonisolated var events: AsyncStream<TransportEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
}

/// Transitions a transport reports out-of-band so the store-side
/// reconnect controller can react. Currently only `.disconnected` is
/// modelled — the controller assumes the transport is healthy until
/// it observes one. Adding `.connecting` / `.reconnected` later is
/// additive and does not require existing consumers to change.
public enum TransportEvent: Sendable, Equatable {
    /// The transport entered a terminal failure state. The associated
    /// `ClientTransportError` is the same value that the next `send` /
    /// `receive` call would also throw, so the controller can use it
    /// directly when surfacing the reason in UI without re-deriving.
    case disconnected(reason: ClientTransportError)
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

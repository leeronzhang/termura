import Foundation
import TermuraRemoteProtocol

public protocol RemoteTransport: Sendable {
    var name: String { get }
    /// Out-of-band health transitions the host can surface in UI.
    /// Conformers without a health signal (LAN, mocks) inherit the
    /// protocol-extension default that finishes immediately, so the
    /// consumer's `for await` loop falls through cleanly.
    nonisolated var events: AsyncStream<ServerTransportEvent> { get }
    func start(handler: any EnvelopeHandler) async throws
    func stop() async
}

public extension RemoteTransport {
    nonisolated var events: AsyncStream<ServerTransportEvent> {
        AsyncStream { continuation in continuation.finish() }
    }
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

/// Transitions a transport reports out-of-band so the host (Mac
/// Settings UI / RemoteControlController) can surface the failure
/// without polling the transport actor every tick.
///
/// Currently only the reply-channel send-failure case is modelled;
/// the existing `pollHealth()` snapshot already covers the inbound
/// poll-loop side. Adding more cases later is additive — consumers
/// drain via `for await` and unknown future cases are ignored by
/// switch defaults.
public enum ServerTransportEvent: Sendable, Equatable {
    /// A virtual reply channel could not deliver an envelope to the
    /// addressed peer. The peer's client side observes "no reply"
    /// via its own request timeout; this event is the only signal
    /// the Mac side itself gets that its outbound pipe is broken,
    /// so Settings UI / logs can show *why* (e.g. CKError reason).
    /// `occurredAt` is captured at the failure site via the
    /// transport's injected clock so consumers do not have to call
    /// `Date()` at the drain hop and risk drifting from the actual
    /// failure time.
    case replyChannelSendFailed(peerDeviceId: UUID, reason: String, occurredAt: Date)
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

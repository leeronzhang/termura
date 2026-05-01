import Foundation

/// Combines `VersionNegotiator` with `Envelope` validation so that both
/// `RemoteEnvelopeRouter` (server) and `RemoteStore` (client) can reject
/// incompatible peers at the receive boundary with one call.
///
/// Returns `nil` when the envelope's protocol version is compatible with the
/// local peer; returns a populated `RemoteError` describing the incompatibility
/// otherwise. Callers are expected to forward the error envelope and close the
/// connection.
public struct VersionGate: Sendable {
    public let negotiator: VersionNegotiator

    public init(negotiator: VersionNegotiator = VersionNegotiator()) {
        self.negotiator = negotiator
    }

    public func check(_ envelope: Envelope) -> RemoteError? {
        switch negotiator.evaluate(remote: envelope.version) {
        case .compatible:
            nil
        case let .remoteTooOld(minimumRequired):
            RemoteError(
                code: .protocolVersionTooOld,
                message: "Remote protocol \(envelope.version) is older than minimum \(minimumRequired)",
                relatedId: envelope.id
            )
        case let .remoteTooNew(maximumSupported):
            RemoteError(
                code: .protocolVersionTooNew,
                message: "Remote protocol \(envelope.version) is newer than maximum supported \(maximumSupported)",
                relatedId: envelope.id
            )
        }
    }
}

// PR8 §3.6 — channel-priming surface for the agent ingress. Lives in
// its own file so the new identity-domain plumbing doesn't inflate the
// main router file (already over `type_body_length` / `file_length`
// budgets from earlier PRs — CLAUDE.md §10 forbids expanding legacy
// debt). `channels`, `phases`, `ChannelState`, and `pairingService`
// are module-internal (rather than `private`) so this same-module
// extension can pattern-match the channel state and call
// `pairingService.recordNegotiation`. They are conceptually private
// to the router; no other type in the module touches them.

import Foundation
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "RemoteEnvelopeRouter+Prime")

extension RemoteEnvelopeRouter {
    /// Installs the `(deviceId, codec)` tuple a channel agreed on
    /// during a prior pair handshake. Used by the agent ingress when
    /// a fresh main-app process — typically one woken by the agent
    /// over XPC — needs to handle a business envelope without
    /// re-running the handshake.
    ///
    /// `channelId` is the **cloudSourceDeviceId** (public-key-derived
    /// id the iPhone uses on the wire). `deviceId` is the
    /// **pairedDeviceId** (business id stored in the channel's
    /// `.authenticated(deviceId:)` value). Naming flags the two
    /// identity domains so callers cannot confuse them; see §3.6.
    ///
    /// Idempotent on `channelId`: a second call with mismatched
    /// `deviceId` or codec keeps the first values and warns.
    /// `TrustedSourceGate` should never produce inconsistent
    /// classifications, so a mismatch surfaces a programming bug
    /// without disrupting the live channel.
    func primeAuthenticatedChannel(
        channelId: UUID,
        deviceId: UUID,
        negotiatedCodec: CodecKind
    ) async {
        if case let .authenticated(currentDeviceId) = channels[channelId, default: .unauthenticated] {
            if currentDeviceId != deviceId {
                logger.warning(
                    "prime: deviceId mismatch on \(channelId); kept \(currentDeviceId), ignored \(deviceId)"
                )
            }
        } else {
            channels[channelId] = .authenticated(deviceId: deviceId)
        }
        if case let .active(currentCodec) = phases[channelId, default: .handshake] {
            if currentCodec != negotiatedCodec {
                logger.warning(
                    "prime: codec mismatch on \(channelId); kept \(currentCodec.rawValue), ignored \(negotiatedCodec.rawValue)"
                )
            }
        } else {
            phases[channelId] = .active(negotiatedCodec)
        }
    }

    /// PR8 — persists `(codec, pairingId)` on the paired-device record
    /// so a fresh main-app process can rebuild `phases` without
    /// re-handshaking. Skipped when peer was on a legacy build (no
    /// pair key to address). Failures only degrade agent-wake replay;
    /// the live session keeps using in-memory phases.
    func persistNegotiation(
        deviceId: UUID,
        codec: CodecKind,
        pairingId: UUID?
    ) async {
        guard let pairingId else { return }
        do {
            try await pairingService.recordNegotiation(
                pairedDeviceId: deviceId,
                negotiatedCodec: codec,
                pairingId: pairingId
            )
        } catch {
            logger.warning("recordNegotiation failed for \(deviceId): \(error.localizedDescription)")
        }
    }
}

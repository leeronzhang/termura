// Late-binding `CloudKitChannelActivator` actor split out of
// `RemoteServerHarness.swift` so that file stays under the
// file_length budget. Lets the router flip the CloudKit transport's
// per-peer reply channel into encrypted mode without holding a
// reference to the transport at the time the activator closure is
// captured. The harness sets the bound transport once it's
// constructed; activations before binding are a no-op (and
// CloudKit-mode handshake on a non-CloudKit-enabled build is
// impossible by construction).
//
// Wave 5 — conforms to the public `CloudKitChannelActivator` protocol
// so the router's call site reads as a typed dependency instead of a
// closure of inscrutable shape.

import Foundation
import TermuraRemoteServer

actor CloudKitActivatorBox: CloudKitChannelActivator {
    private weak var transport: CloudKitTransport?

    func bind(transport: CloudKitTransport) {
        self.transport = transport
    }

    func activate(pairingId: UUID, forSourceDeviceId source: UUID) async {
        await transport?.setActivePairingId(pairingId, forSourceDeviceId: source)
    }
}

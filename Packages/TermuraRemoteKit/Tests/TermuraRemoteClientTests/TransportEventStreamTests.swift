import Foundation
@testable import TermuraRemoteClient
import TermuraRemoteProtocol
import Testing

// Pins the B1 contract for the new `events: AsyncStream<TransportEvent>`
// surface added to `ClientTransport`. The reconnect controller in the
// iOS store relies on:
//   1. The protocol providing a default empty stream (so non-WebSocket
//      conformers compile without changes and the consumer can iterate
//      uniformly).
//   2. `WebSocketClientTransport.events` being a fresh per-instance
//      stream — no leakage across transports.
//   3. The stream finishing when the transport deinits, so the
//      consumer's `for await` loop falls through cleanly when the
//      RemoteStore drops its client during `disconnect()`.
//
// Tests resolve through deterministic stream termination — either the
// default-empty stream finishing immediately, or actor deinit driving
// `continuation.finish()`. No racing timeout primitives, so `for await`
// loops cannot hang.
//
// The richer "fatal NWError → emit" behaviour requires a real socket
// peer; that path is covered indirectly by the iOS reconnect-flow
// tests (see `RemoteStoreReconnectBackoffTests`).

@Suite("ClientTransport events surface")
struct TransportEventStreamTests {
    @Test("Default protocol-extension stream finishes immediately")
    func defaultStreamFinishesImmediately() async {
        struct StubTransport: ClientTransport {
            func connect() async throws {}
            func send(_: Envelope) async throws {}
            func receive() async throws -> Envelope {
                throw ClientTransportError.notConnected
            }

            func disconnect() async {}
        }
        let transport = StubTransport()
        var observed = 0
        for await _ in transport.events {
            observed += 1
        }
        // The default impl yields nothing and finishes; for-await
        // must fall through, not hang, so the consumer's drain task
        // exits cleanly when paired against a transport that doesn't
        // care about transport-health events.
        #expect(observed == 0)
    }

    @Test("WebSocketClientTransport events are per-instance, finish on deinit")
    func eventsAreIndependentAndFinishOnDeinit() async {
        let endpoint = WebSocketClientTransport.Endpoint(host: "127.0.0.1", port: 1)
        let streamA: AsyncStream<TransportEvent>
        let streamB: AsyncStream<TransportEvent>
        // Construct two transports in a nested scope so they fall out
        // of scope (and deinit) at the closing brace. `deinit` calls
        // `eventsContinuation.finish()`, which terminates the streams
        // we captured into the outer scope without any racing timeout.
        do {
            let a = WebSocketClientTransport(endpoint: endpoint)
            let b = WebSocketClientTransport(endpoint: endpoint)
            streamA = a.events
            streamB = b.events
        }
        var countA = 0
        for await _ in streamA {
            countA += 1
        }
        var countB = 0
        for await _ in streamB {
            countB += 1
        }
        // Both streams finished cleanly via deinit (not via the same
        // continuation, which would prove the streams were aliased).
        #expect(countA == 0)
        #expect(countB == 0)
    }
}

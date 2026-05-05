import Foundation
import Network
@testable import TermuraRemoteClient
import Testing

// Pins the contract of `LANBrowser.map(nwState:)` — the pure mapping from
// `NWBrowser.State` to the public `LANBrowserState` that RemoteStore uses
// to drive the pairing-page hint. Without this guarantee, an iOS SDK bump
// that introduces a new `NWBrowser.State` case could silently regress the
// "Local Network permission denied" recovery path: we'd fall through to
// `.idle` (the `@unknown default` arm) and the user would be back in the
// dead-spinner UX the fix was meant to eliminate.

@Suite("LANBrowser state mapping")
struct LANBrowserStateMappingTests {
    @Test("setup → idle")
    func setupMapsToIdle() {
        #expect(LANBrowser.map(nwState: .setup) == .idle)
    }

    @Test("ready → browsing")
    func readyMapsToBrowsing() {
        #expect(LANBrowser.map(nwState: .ready) == .browsing)
    }

    @Test("waiting carries the localizedDescription")
    func waitingCarriesReason() {
        let nwError = NWError.posix(.EPERM)
        let state = LANBrowser.map(nwState: .waiting(nwError))
        if case let .waiting(reason) = state {
            #expect(reason == nwError.localizedDescription)
        } else {
            Issue.record("expected .waiting(...), got \(state)")
        }
    }

    @Test("failed carries the localizedDescription")
    func failedCarriesReason() {
        let nwError = NWError.posix(.ENETDOWN)
        let state = LANBrowser.map(nwState: .failed(nwError))
        if case let .failed(reason) = state {
            #expect(reason == nwError.localizedDescription)
        } else {
            Issue.record("expected .failed(...), got \(state)")
        }
    }

    @Test("cancelled → cancelled")
    func cancelledMapsToCancelled() {
        #expect(LANBrowser.map(nwState: .cancelled) == .cancelled)
    }

    @Test("LANBrowserState equality covers all cases")
    func equalityCoverage() {
        #expect(LANBrowserState.idle == .idle)
        #expect(LANBrowserState.browsing == .browsing)
        #expect(LANBrowserState.cancelled == .cancelled)
        #expect(LANBrowserState.waiting(reason: "x") == .waiting(reason: "x"))
        #expect(LANBrowserState.waiting(reason: "x") != .waiting(reason: "y"))
        #expect(LANBrowserState.failed(reason: "x") == .failed(reason: "x"))
        #expect(LANBrowserState.failed(reason: "x") != .failed(reason: "y"))
        #expect(LANBrowserState.idle != .browsing)
    }
}

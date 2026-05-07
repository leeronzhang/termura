@testable import Termura
import XCTest

@MainActor
final class SessionListBroadcasterTests: XCTestCase {
    func testPingNowYieldsOncePerSnapshotChange() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        var snapshot: [UUID] = [UUID()]
        let broadcaster = SessionListBroadcaster(
            coordinator: ProjectCoordinator(),
            changeContinuation: continuation,
            snapshotProvider: { snapshot }
        )

        broadcaster.pingNow() // first call locks in [a]
        broadcaster.pingNow() // identical → must NOT yield
        snapshot = [UUID(), UUID()] // simulate a session opening
        broadcaster.pingNow() // changed → must yield
        snapshot = [] // simulate the engine dying
        broadcaster.pingNow() // changed → must yield
        broadcaster.pingNow() // identical → must NOT yield

        continuation.finish()
        var count = 0
        for await _ in stream {
            count += 1
        }
        XCTAssertEqual(count, 3, "Three distinct snapshots, three yields; duplicates are dropped")
    }

    func testPingNowOnEmptyInitialSnapshotIsCoalescedAfterFirst() async {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let broadcaster = SessionListBroadcaster(
            coordinator: ProjectCoordinator(),
            changeContinuation: continuation,
            snapshotProvider: { [] }
        )

        // First ping with an empty snapshot is itself a transition from
        // the initial `lastSnapshot = []` baseline; it must not yield
        // because nothing observable has changed.
        broadcaster.pingNow()
        broadcaster.pingNow()

        continuation.finish()
        var count = 0
        for await _ in stream {
            count += 1
        }
        XCTAssertEqual(count, 0, "Empty → empty is a no-op")
    }
}

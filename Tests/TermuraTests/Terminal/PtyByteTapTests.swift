@testable import Termura
import XCTest

@MainActor
final class PtyByteTapTests: XCTestCase {
    func testSubscribeYieldsToSingleSubscriber() async throws {
        let tap = PtyByteTap()
        let sub = tap.subscribe()
        let receiver = Task<Data, Never> {
            for await chunk in sub.stream {
                return chunk
            }
            return Data()
        }
        let payload = Data([0x68, 0x65, 0x6C, 0x6C, 0x6F])
        tap.feedNonisolated(payload)
        let got = await receiver.value
        XCTAssertEqual(got, payload)
    }

    func testSubscribeFanOutsToAllSubscribers() async throws {
        let tap = PtyByteTap()
        let first = tap.subscribe()
        let second = tap.subscribe()
        let third = tap.subscribe()

        let recv: (PtyByteTap.Subscription) -> Task<Data, Never> = { sub in
            Task {
                for await chunk in sub.stream {
                    return chunk
                }
                return Data()
            }
        }
        let r1 = recv(first)
        let r2 = recv(second)
        let r3 = recv(third)
        let payload = Data([0xAB, 0xCD, 0xEF])
        tap.feedNonisolated(payload)

        let g1 = await r1.value
        let g2 = await r2.value
        let g3 = await r3.value
        XCTAssertEqual(g1, payload)
        XCTAssertEqual(g2, payload)
        XCTAssertEqual(g3, payload)
    }

    func testUnsubscribeFinishesOnlyThatStream() async throws {
        let tap = PtyByteTap()
        let a = tap.subscribe()
        let b = tap.subscribe()

        // Cancel only A. B must continue receiving.
        tap.unsubscribe(id: a.id)

        // A's stream finishes — for-await sees no element and returns.
        let aFinished = Task<Bool, Never> {
            for await _ in a.stream {
                return false
            }
            return true
        }
        let bReceived = Task<Data, Never> {
            for await chunk in b.stream {
                return chunk
            }
            return Data()
        }

        let payload = Data([0x77])
        tap.feedNonisolated(payload)
        let aDone = await aFinished.value
        let bGot = await bReceived.value
        XCTAssertTrue(aDone)
        XCTAssertEqual(bGot, payload)
    }

    func testFinishAllFinishesEverySubscription() async throws {
        let tap = PtyByteTap()
        let a = tap.subscribe()
        let b = tap.subscribe()
        tap.finishAll()

        let aDone = Task<Bool, Never> {
            for await _ in a.stream {
                return false
            }
            return true
        }
        let bDone = Task<Bool, Never> {
            for await _ in b.stream {
                return false
            }
            return true
        }
        let aFinished = await aDone.value
        let bFinished = await bDone.value
        XCTAssertTrue(aFinished)
        XCTAssertTrue(bFinished)

        // After finishAll, new subscribe() returns a stream that finishes
        // immediately so a late subscriber doesn't block forever.
        let late = tap.subscribe()
        let lateDone = Task<Bool, Never> {
            for await _ in late.stream {
                return false
            }
            return true
        }
        let lateFinished = await lateDone.value
        XCTAssertTrue(lateFinished)
    }

    func testActiveSubscriberCountTracksLifecycle() async throws {
        let tap = PtyByteTap()
        XCTAssertEqual(tap.activeSubscriberCount, 0)
        let a = tap.subscribe()
        XCTAssertEqual(tap.activeSubscriberCount, 1)
        let b = tap.subscribe()
        XCTAssertEqual(tap.activeSubscriberCount, 2)
        tap.unsubscribe(id: a.id)
        XCTAssertEqual(tap.activeSubscriberCount, 1)
        tap.finishAll()
        XCTAssertEqual(tap.activeSubscriberCount, 0)
        _ = b // silence unused-warning; b's lifecycle is asserted via count
    }

    func testFeedPreservesByteOrderAcrossManyChunks() async throws {
        // Critical: VT/ANSI escape sequences depend on byte order.
        // Multiple sequential `feedNonisolated` calls from the IO thread
        // must arrive at the subscriber in the same order — even when
        // the source thread is non-MainActor. Earlier `Task { await }`
        // implementation lost ordering because Task enqueues are not
        // FIFO into an actor.
        let tap = PtyByteTap()
        let sub = tap.subscribe()

        let receiver = Task<[Data], Never> {
            var collected: [Data] = []
            for await chunk in sub.stream {
                collected.append(chunk)
                if collected.count == 100 { break }
            }
            return collected
        }

        await Task.detached {
            for byte in (0 ..< 100).map({ UInt8($0 & 0xFF) }) {
                tap.feedNonisolated(Data([byte]))
            }
        }.value

        let received = await receiver.value
        XCTAssertEqual(received.count, 100)
        XCTAssertEqual(
            received.compactMap(\.first),
            (0 ..< 100).map { UInt8($0 & 0xFF) },
            "Byte order must be preserved end-to-end through the tap"
        )
    }

    func testFeedFromIOThreadIsNonBlocking() async throws {
        // Sanity floor on hold time: 100 small feeds should complete in
        // well under 100 ms even with one slow subscriber. If the lock
        // hold time degrades (e.g. someone changes yield to be blocking)
        // this test catches it before it ships.
        let tap = PtyByteTap()
        _ = tap.subscribe() // intentionally never drained — back-pressure
        // is bounded by `bufferingNewest`, so feed must not stall.
        let start = ContinuousClock().now
        for byte in (0 ..< 100).map({ UInt8($0 & 0xFF) }) {
            tap.feedNonisolated(Data([byte]))
        }
        let duration = ContinuousClock().now - start
        XCTAssertLessThan(duration, .milliseconds(100))
    }
}

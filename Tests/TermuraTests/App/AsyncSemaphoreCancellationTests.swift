import Foundation
@testable import Termura
import XCTest

final class AsyncSemaphoreCancellationTests: XCTestCase {
    func testCancelledWaiterDoesNotLeakPermit() async {
        let semaphore = AsyncSemaphore(value: 1)
        await semaphore.wait()

        let cancelled = Task {
            await semaphore.wait()
        }
        await Task.yield()
        cancelled.cancel()
        _ = await cancelled.result

        await semaphore.signal()

        let acquired = LockIsolated(false)
        let follower = Task {
            await semaphore.wait()
            acquired.withValue { $0 = true }
            await semaphore.signal()
        }

        for _ in 0 ..< 20 {
            if acquired.value { break }
            await Task.yield()
        }

        XCTAssertTrue(acquired.value)
        _ = await follower.result
    }
}

/// NSLock serializes all reads/writes to `storage`; test helper only stores small value types.
private final class LockIsolated<Value>: @unchecked Sendable { // swiftlint:disable:this unchecked_sendable_documentation
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withValue(_ update: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        update(&storage)
    }
}

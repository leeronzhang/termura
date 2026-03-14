import Testing
@testable import Termura

@Suite("InputHistory")
struct InputHistoryTests {

    // MARK: - Basic push/navigate

    @Test("navigatePrevious returns most recent entry")
    func navigatePreviousReturnsMostRecent() {
        var history = InputHistory(capacity: 10)
        history.push("ls -la")
        let result = history.navigatePrevious()
        #expect(result == "ls -la")
    }

    @Test("navigatePrevious returns entries in reverse push order")
    func navigatePreviousOrder() {
        var history = InputHistory(capacity: 10)
        history.push("first")
        history.push("second")
        history.push("third")

        #expect(history.navigatePrevious() == "third")
        #expect(history.navigatePrevious() == "second")
        #expect(history.navigatePrevious() == "first")
    }

    @Test("navigateNext returns newer entry after going back")
    func navigateNextAfterPrevious() {
        var history = InputHistory(capacity: 10)
        history.push("first")
        history.push("second")

        _ = history.navigatePrevious() // second
        _ = history.navigatePrevious() // first
        let result = history.navigateNext() // back to second
        #expect(result == "second")
    }

    @Test("navigateNext at present returns nil")
    func navigateNextAtPresent() {
        var history = InputHistory(capacity: 10)
        history.push("cmd")

        _ = history.navigatePrevious()
        _ = history.navigateNext() // back to present
        let result = history.navigateNext()
        #expect(result == nil)
    }

    // MARK: - Empty history

    @Test("navigatePrevious on empty history returns nil")
    func navigatePreviousEmpty() {
        var history = InputHistory(capacity: 10)
        let result = history.navigatePrevious()
        #expect(result == nil)
    }

    // MARK: - Push behavior

    @Test("Push empty string is ignored")
    func pushEmptyIgnored() {
        var history = InputHistory(capacity: 10)
        history.push("")
        history.push("   ")
        let result = history.navigatePrevious()
        #expect(result == nil)
    }

    @Test("Push resets cursor")
    func pushResetsCursor() {
        var history = InputHistory(capacity: 10)
        history.push("first")
        _ = history.navigatePrevious()
        history.push("second") // cursor should reset
        let result = history.navigatePrevious()
        #expect(result == "second")
    }

    // MARK: - Capacity / circular buffer

    @Test("Capacity is respected — oldest entry evicted")
    func capacityEviction() {
        var history = InputHistory(capacity: 3)
        history.push("a")
        history.push("b")
        history.push("c")
        history.push("d") // evicts "a"

        #expect(history.navigatePrevious() == "d")
        #expect(history.navigatePrevious() == "c")
        #expect(history.navigatePrevious() == "b")
        // "a" should be gone
        let shouldBeB = history.navigatePrevious()
        // With capacity 3, we only have 3 entries; navigating again stays at oldest
        #expect(shouldBeB == "b")
    }

    @Test("Circular overwrite: newest always accessible")
    func circularOverwrite() {
        var history = InputHistory(capacity: 2)
        history.push("x")
        history.push("y")
        history.push("z") // overwrites "x"

        #expect(history.navigatePrevious() == "z")
        #expect(history.navigatePrevious() == "y")
    }

    // MARK: - resetCursor

    @Test("resetCursor restarts navigation from present")
    func resetCursor() {
        var history = InputHistory(capacity: 10)
        history.push("cmd1")
        history.push("cmd2")

        _ = history.navigatePrevious() // cmd2
        _ = history.navigatePrevious() // cmd1
        history.resetCursor()

        // After reset, navigatePrevious should return newest again
        #expect(history.navigatePrevious() == "cmd2")
    }
}

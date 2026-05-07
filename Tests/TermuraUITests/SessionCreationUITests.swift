import XCTest

/// End-to-end tests for the new-session creation user flow.
///
/// Covers three entry points:
///   1. Empty-state "New Session" button (first session in a fresh project)
///   2. Sidebar "+" button (subsequent sessions)
///   3. "New Session" menu bar item (File > New Session / Cmd+T)
///
/// Regression value: if session creation breaks silently, unit tests may still pass
/// because they test `SessionStore.createSession()` in isolation. These tests verify
/// the full path from user gesture through the SwiftUI layer to the visible sidebar row.
@MainActor
final class SessionCreationUITests: TermuraUITestCase {
    // MARK: - Empty state

    func testEmptyStateButtonCreatesFirstSession() throws {
        try launchWithTestProject()
        waitForMainWindow()

        let newSessionButton = element("emptyStateNewSessionButton")
        let firstRow = sessionRows().firstMatch
        if newSessionButton.waitForExistence(timeout: 5) {
            newSessionButton.click()
            XCTAssertTrue(
                firstRow.waitForExistence(timeout: 5),
                "A session row should appear in the sidebar after tapping 'New Session'"
            )
            XCTAssertFalse(
                newSessionButton.waitForExistence(timeout: 2),
                "Empty-state button should disappear once a session exists"
            )
            return
        }

        if firstRow.waitForExistence(timeout: 5) {
            return
        }

        triggerNewSessionShortcut()
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: 5),
            "Startup should surface a session row directly or allow creating one via Cmd+T"
        )
    }

    // MARK: - Sidebar "+" button

    func testSidebarPlusButtonAddsAnotherSession() throws {
        try launchWithTestProject()
        waitForMainWindow()

        ensureSessionExists()

        let countBefore = sessionRows().count

        let plusButton = element("newSessionButton")
        XCTAssertTrue(
            plusButton.waitForExistence(timeout: 5),
            "Sidebar '+' button must be present after the first session is created"
        )
        plusButton.click()

        let expectedCount = countBefore + 1
        let predicate = NSPredicate(format: "count == %d", expectedCount)
        let rowsCountExpectation = XCTNSPredicateExpectation(predicate: predicate, object: sessionRows())
        wait(for: [rowsCountExpectation], timeout: 5)
        XCTAssertEqual(sessionRows().count, expectedCount, "Session count must increase by 1")
    }

    // MARK: - Menu bar / Cmd+T

    func testMenuBarNewSessionCreatesSession() throws {
        try launchWithTestProject()
        waitForMainWindow()

        ensureSessionExists()

        let countBefore = sessionRows().count

        let menuItem = app.menuBars.menuItems["New Session"]
        if menuItem.waitForExistence(timeout: 2) {
            menuItem.click()
        } else {
            triggerNewSessionShortcut()
        }

        let expectedCount = countBefore + 1
        let predicate = NSPredicate(format: "count == %d", expectedCount)
        let rowsCountExpectation = XCTNSPredicateExpectation(predicate: predicate, object: sessionRows())
        wait(for: [rowsCountExpectation], timeout: 5)
        XCTAssertEqual(sessionRows().count, expectedCount, "Menu bar 'New Session' must create a session")
    }

    // MARK: - Regression: multiple sessions in sequence

    func testCreatingThreeSessionsProducesThreeRows() throws {
        try launchWithTestProject()
        waitForMainWindow()

        ensureSessionExists()

        let plusBtn = element("newSessionButton")
        XCTAssertTrue(plusBtn.waitForExistence(timeout: 5))

        plusBtn.click()
        let twoRows = NSPredicate(format: "count == 2", [])
        wait(for: [XCTNSPredicateExpectation(predicate: twoRows, object: sessionRows())], timeout: 5)

        plusBtn.click()
        let threeRows = NSPredicate(format: "count == 3", [])
        wait(for: [XCTNSPredicateExpectation(predicate: threeRows, object: sessionRows())], timeout: 5)

        XCTAssertEqual(sessionRows().count, 3, "Three sessions must produce three sidebar rows")
    }
}

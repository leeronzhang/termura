import XCTest

/// Base class for Termura UI automation tests.
///
/// Provides a pre-configured `XCUIApplication` with isolated environment variables
/// that redirect the app away from the user's real data directory and suppress
/// interactive prompts (shell onboarding, project picker).
///
/// Usage:
/// ```swift
/// final class MyFlowTests: TermuraUITestCase {
///     func testSomething() throws {
///         try launchWithTestProject()
///         waitForMainWindow()
///         // ... interact via `app`
///     }
/// }
/// ```
@MainActor
class TermuraUITestCase: XCTestCase {
    private var application: XCUIApplication?
    private var startupReadinessIdentifiers: [String] {
        [
            "emptyStateNewSessionButton",
            "newSessionButton",
            "sessionRow",
            "installHookButton",
            "skipOnboardingButton",
            "shellTypePicker"
        ]
    }

    var app: XCUIApplication {
        guard let application else {
            fatalError("XCUIApplication accessed before setUpWithError")
        }
        return application
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        application = XCUIApplication(bundleIdentifier: "com.termura.app")
    }

    override func tearDownWithError() throws {
        app.terminate()
        application = nil
        try super.tearDownWithError()
    }

    // MARK: - Launch helpers

    /// Launches the app with an isolated temporary project directory.
    ///
    /// - Parameter skipOnboarding: When `true` (default), sets the shell-integration
    ///   installed flag so the onboarding sheet is suppressed. Pass `false` to let
    ///   the onboarding sheet appear for onboarding-specific tests.
    /// - Parameter mockShellInstaller: When `true` (default), the app uses
    ///   `MockShellHookInstaller` so Install Hook never writes to `~/.zshrc`.
    /// - Returns: The temporary project URL. The directory is deleted in teardown.
    @discardableResult
    func launchWithTestProject(
        skipOnboarding: Bool = true,
        mockShellInstaller: Bool = true
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("TermuraUITest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        addTeardownBlock {
            do {
                try FileManager.default.removeItem(at: tmp)
            } catch {
                XCTFail("Failed to clean up UI test temp directory at \(tmp.path): \(error.localizedDescription)")
            }
        }

        app.launchEnvironment["UI_TESTING_PROJECT_PATH"] = tmp.path
        if skipOnboarding {
            app.launchEnvironment["UI_TESTING_SKIP_SHELL_ONBOARDING"] = "1"
        }
        if mockShellInstaller {
            app.launchEnvironment["UI_TESTING_MOCK_SHELL_INSTALLER"] = "1"
        }
        app.launchEnvironment["UI_TESTING_MOCK_TERMINAL_ENGINE"] = "1"
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        // XCUITest launches Termura into the background by default; activate it so its
        // windows become visible to the AX hierarchy. Without this the app stays
        // `runningBackground` and `app.windows` is empty even though the project window
        // was created on the Cocoa side. Repeat until state flips to runningForeground
        // or we give up — the first activate() call often races against app launch.
        let activationDeadline = Date().addingTimeInterval(10)
        while Date() < activationDeadline, app.state != .runningForeground {
            app.activate()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return tmp
    }

    // MARK: - Wait helpers

    /// Waits for the main project window to become visible.
    func waitForMainWindow(timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        let window = app.windows.firstMatch

        while Date() < deadline {
            if window.exists || startupReadinessIdentifiers.contains(where: startupElementExists(identifier:)) {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTFail("Main project window should appear within \(timeout)s")
    }

    /// Returns an element query matching all session rows in the sidebar.
    func sessionRows() -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "sessionRow")
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// Ensures the app has at least one visible session, whether it was restored/auto-created
    /// during startup or still needs to be created via the empty-state CTA.
    @discardableResult
    func ensureSessionExists(timeout: TimeInterval = 5) -> XCUIElement {
        let firstRow = sessionRows().firstMatch
        if firstRow.waitForExistence(timeout: timeout) {
            return firstRow
        }

        let newSessionButton = element("emptyStateNewSessionButton")
        if newSessionButton.waitForExistence(timeout: timeout) {
            newSessionButton.click()
            XCTAssertTrue(
                firstRow.waitForExistence(timeout: timeout),
                "A session row should appear after clicking the empty-state 'New Session' button"
            )
            return firstRow
        }

        let sidebarNewSessionButton = element("newSessionButton")
        if sidebarNewSessionButton.waitForExistence(timeout: timeout) {
            sidebarNewSessionButton.click()
            XCTAssertTrue(
                firstRow.waitForExistence(timeout: timeout),
                "A session row should appear after clicking the sidebar '+' button"
            )
            return firstRow
        }

        triggerNewSessionShortcut()
        XCTAssertTrue(
            firstRow.waitForExistence(timeout: timeout),
            "A session row should appear after triggering the global 'New Session' command"
        )
        return firstRow
    }

    func triggerNewSessionShortcut() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5), "A window must exist before sending Cmd+T")
        window.click()
        app.typeKey("t", modifierFlags: .command)
    }

    private func startupElementExists(identifier: String) -> Bool {
        element(identifier).exists
    }
}

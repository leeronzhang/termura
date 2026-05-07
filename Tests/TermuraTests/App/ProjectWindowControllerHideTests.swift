import AppKit
@testable import Termura
import XCTest

@MainActor
final class ProjectWindowControllerHideTests: XCTestCase {
    private var context: ProjectContext?
    private var controller: ProjectWindowController?
    private var tmpDir: URL?

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpDir = dir

        let factory = MockTerminalEngineFactory()
        let ctx = try await ProjectContext.open(
            at: dir,
            engineFactory: factory,
            tokenCountingService: TokenCountingService()
        )
        context = ctx
        controller = ProjectWindowController(
            projectContext: ctx,
            themeManager: ThemeManager(),
            fontSettings: FontSettings(),
            webViewPool: WebViewPool(),
            webRendererBridge: WebRendererBridge()
        )
    }

    override func tearDown() async throws {
        controller?.close()
        controller = nil
        await context?.close()
        context = nil
        if let dir = tmpDir {
            do {
                try FileManager.default.removeItem(at: dir)
            } catch {
                // Non-critical: test scratch directory cleanup; surface for debugging only.
                print("tearDown cleanup failed for \(dir.path): \(error)")
            }
        }
    }

    // MARK: - Happy path: traffic-light close hides

    func testWindowShouldCloseVetoesAndHides() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)

        let shouldClose = controller.windowShouldClose(window)

        XCTAssertFalse(shouldClose, "Close must be vetoed so the window only hides.")
        XCTAssertTrue(controller.isHiddenByUser, "Hide flag must be set after close request.")
        XCTAssertTrue(window.isExcludedFromWindowsMenu, "Hidden window drops out of the Window menu.")
    }

    // MARK: - Lifecycle: engines survive hide

    /// The whole point of the shoebox-close fix: hiding the window must not
    /// terminate the project's PTY engines. Sessions need to outlive window UI.
    func testHidePreservesEngineStore() throws {
        let context = try XCTUnwrap(context)
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        let sessionID = SessionID()
        context.sessionScope.engines.createEngine(for: sessionID)
        XCTAssertNotNil(context.sessionScope.engines.engine(for: sessionID), "Precondition")

        _ = controller.windowShouldClose(window)

        XCTAssertNotNil(
            context.sessionScope.engines.engine(for: sessionID),
            "Engine must survive a user-hide — sessions persist while app is alive."
        )
    }

    // MARK: - Restore reverses hide

    func testRestoreClearsHideFlag() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        _ = controller.windowShouldClose(window)
        XCTAssertTrue(controller.isHiddenByUser, "Precondition")

        controller.restore()

        XCTAssertFalse(controller.isHiddenByUser, "Restore must clear the hide flag.")
        XCTAssertFalse(window.isExcludedFromWindowsMenu, "Restored window rejoins the Window menu.")
    }

    func testRestoreOnVisibleControllerIsIdempotent() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(controller.isHiddenByUser, "Precondition: never hidden")

        controller.restore()

        XCTAssertFalse(controller.isHiddenByUser)
        XCTAssertFalse(window.isExcludedFromWindowsMenu)
    }

    // MARK: - Fullscreen close path (zombie-Space regression)

    // Regression for the bug where closing a window via the red traffic light
    // while in fullscreen left a phantom Space behind (no content, no chrome,
    // no exit). The fix defers `orderOut(_:)` until AppKit finishes the
    // fullscreen-exit animation, signalled via `windowDidExitFullScreen`.
    //
    // We can't drive `NSWindow.styleMask` to include `.fullScreen` from a unit
    // test — AppKit logs and rejects bit-flips that happen outside a real
    // fullscreen transition. Instead we exercise the deferred-orderOut branch
    // directly by setting the controller's deferral flag, which the production
    // hideForUser() flips when it observes the styleMask in fullscreen.

    func testWindowDidExitFullScreenDuringHideClearsDeferralFlag() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        controller.isExitingFullScreenForHide = true

        controller.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))

        XCTAssertFalse(
            controller.isExitingFullScreenForHide,
            "Deferral flag must clear once orderOut has been issued."
        )
        XCTAssertFalse(window.isVisible, "Deferred orderOut must hide the window once fullscreen exit completes.")
    }

    func testWindowDidExitFullScreenWithoutDeferralIsNoop() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(controller.isExitingFullScreenForHide, "Precondition: no hide in flight.")

        controller.windowDidExitFullScreen(Notification(name: NSWindow.didExitFullScreenNotification, object: window))

        XCTAssertFalse(
            controller.isExitingFullScreenForHide,
            "A normal fullscreen exit must leave the deferral flag untouched."
        )
    }

    func testRestoreClearsFullScreenDeferralFlag() throws {
        let controller = try XCTUnwrap(controller)
        let window = try XCTUnwrap(controller.window)
        // hideForUser drives the windowed-hide branch (not in fullscreen here);
        // we then simulate the deferred-fullscreen-exit state on top of it.
        _ = controller.windowShouldClose(window)
        controller.isExitingFullScreenForHide = true

        controller.restore()

        XCTAssertFalse(controller.isHiddenByUser, "Restore must clear the hide flag.")
        XCTAssertFalse(
            controller.isExitingFullScreenForHide,
            "Restoring before exit-fullscreen finishes must abandon the deferred orderOut."
        )
    }
}

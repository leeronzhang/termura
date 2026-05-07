import Foundation
@testable import Termura
import XCTest

final class UserShellEnvironmentTests: XCTestCase {
    func testProbeReturnsNonEmptyPath() async {
        let env = UserShellEnvironment()
        let path = await env.resolvedPath()
        XCTAssertFalse(path.isEmpty, "PATH probe must return a non-empty value (probed or fallback)")
        // Validate it looks like a PATH (colon-separated absolute paths).
        XCTAssertTrue(path.contains("/"), "PATH should contain at least one absolute path entry")
    }

    func testProbeIsCachedAcrossCalls() async {
        let env = UserShellEnvironment()
        let first = await env.resolvedPath()
        let second = await env.resolvedPath()
        XCTAssertEqual(first, second)
    }

    func testStaticUserShellEnvironmentReturnsInjectedPath() async {
        let mock = StaticUserShellEnvironment(path: "/custom/bin:/other/bin")
        let value = await mock.resolvedPath()
        XCTAssertEqual(value, "/custom/bin:/other/bin")
    }
}

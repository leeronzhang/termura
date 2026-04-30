import Foundation
@testable import Termura
import XCTest

final class RemoteHelperPathResolverTests: XCTestCase {
    func testResolvesRelativeToInjectedBundleURL() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-resolver-tests-\(UUID().uuidString)")
            .appendingPathComponent("Termura.app")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bundle = try XCTUnwrap(Bundle(url: tempDir) ?? Bundle(path: tempDir.path))
        let resolver = LiveRemoteHelperPathResolver(bundle: bundle)

        let url = resolver.helperExecutableURL()

        XCTAssertEqual(
            url.path,
            tempDir.appendingPathComponent("Contents/Helpers/termura-remote-agent").path
        )
    }

    func testReturnsURLEvenWhenBundleHasNoContentsDirectory() throws {
        // Fake bundle root that doesn't have a Contents/ subdirectory yet —
        // resolver must still produce a URL and let the health check decide
        // whether it actually points at a real file.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-resolver-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let bundle = try XCTUnwrap(Bundle(url: tempDir) ?? Bundle(path: tempDir.path))
        let resolver = LiveRemoteHelperPathResolver(bundle: bundle)

        let url = resolver.helperExecutableURL()

        XCTAssertTrue(url.path.hasSuffix("Contents/Helpers/termura-remote-agent"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testProductionResolverReadsBundleMain() {
        // Bundle.main inside an XCTest run is the test bundle, not Termura.app.
        // We don't assert a specific path — we only assert the resolver does
        // not crash and returns a URL that ends in the helper relative path.
        let resolver = LiveRemoteHelperPathResolver()
        let url = resolver.helperExecutableURL()
        XCTAssertTrue(url.path.hasSuffix("Contents/Helpers/termura-remote-agent"))
    }
}

import Foundation
@testable import Termura

/// Test-only helper-path resolver. Construct with `makeBundledHelper(in:name:)`
/// to fabricate a real on-disk binary at a tempDir-relative path with the
/// executable bit set; the controller's PR10 health check will treat the
/// fake as a real bundled helper.
///
/// Use the no-op `init(path:)` overload when a test needs the resolver to
/// point at a path that deliberately does NOT exist (helperNotBundled
/// scenarios) or that exists without the executable bit
/// (helperNotExecutable).
struct StubHelperPathResolver: RemoteHelperPathResolving {
    let path: String

    func helperExecutableURL() -> URL { URL(fileURLWithPath: path) }

    /// Writes a tiny placeholder file under `directory/name`, chmods it
    /// to `0o755`, and returns a resolver pointing at that path. The
    /// caller is responsible for `directory` cleanup; the file lives
    /// inside `directory` so removing the directory removes the helper.
    static func makeBundledHelper(
        in directory: URL,
        name: String,
        contents: Data = Data([0xCA, 0xFE, 0xBA, 0xBE])
    ) throws -> StubHelperPathResolver {
        let helperURL = directory.appendingPathComponent(name)
        try contents.write(to: helperURL)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: helperURL.path
        )
        return StubHelperPathResolver(path: helperURL.path)
    }
}

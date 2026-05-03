// Resolves the absolute path to the bundled `termura-remote-agent` helper
// binary. The resolver is the only place in the codebase that decides where
// the helper lives; PR10 routes every plist write, install-time health
// check, and reinstallIfNeeded comparison through this single seam so a
// release that ends up outside `/Applications/` (DerivedData, beta channel,
// drag-installed elsewhere) keeps a consistent path.
//
// The protocol exists so tests can inject a fake bundle pointing at a
// tempDir with a fabricated helper file; production code uses
// `LiveRemoteHelperPathResolver(bundle: .main)`.

import Foundation

/// Relative path of the helper inside `Termura.app/`. Owned here so the
/// private build script and the runtime resolver have a single source of
/// truth for the layout under `Contents/Helpers/`.
enum RemoteHelperLayout {
    static let executableRelativePath = "Contents/Helpers/termura-remote-agent"
}

protocol RemoteHelperPathResolving: Sendable {
    func helperExecutableURL() -> URL
}

/// Resolves the helper path relative to a `Bundle`. The bundle URL is
/// captured at init time so the resolver itself is `Sendable`; `Bundle`
/// is not.
struct LiveRemoteHelperPathResolver: RemoteHelperPathResolving {
    private let bundleURL: URL

    init(bundle: Bundle = .main) {
        bundleURL = bundle.bundleURL
    }

    func helperExecutableURL() -> URL {
        bundleURL.appendingPathComponent(RemoteHelperLayout.executableRelativePath)
    }
}

/// Surfaced by enable() when the helper binary is missing or non-executable
/// at the resolved path. Distinct cases let the UI/log layer differentiate
/// "this build doesn't include a helper at all" from "the helper exists
/// but lacks the executable bit".
enum RemoteHelperError: Error, Sendable, Equatable {
    case helperNotBundled(path: String)
    case helperNotExecutable(path: String)
}

extension RemoteHelperError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .helperNotBundled(path):
            "Remote helper is not bundled at \(path)."
        case let .helperNotExecutable(path):
            "Remote helper at \(path) is not executable."
        }
    }
}

// Read-only diagnostic snapshot of the remote-agent helper's installation
// state. Combines three independent inputs:
//
//   1. The path the resolver would write into a fresh plist
//   2. The path the on-disk plist is actually pointing at (if any)
//   3. A fingerprint comparison against the last successful install
//
// The struct is a pure value — `inspect(...)` is the factory that consults
// resolver, installer, and the file system. Step 3 will layer
// fingerprint persistence on top; Step 1 surfaces the path-level bits and
// leaves `fingerprintMatchesLastInstall` `true` when no prior fingerprint
// is supplied (we have nothing to mismatch against, so we don't trigger
// reinstall on first use).

import Foundation

/// Lightweight stat triple used to detect helper-binary upgrades without
/// a cryptographic hash. Stored in `UserDefaults` keyed by
/// `AppConfig.UserDefaultsKeys.remoteHelperLastInstalledFingerprint`
/// in Step 3.
///
/// `path` is included so a relocate (e.g. `/Applications/...` →
/// DerivedData) trips the comparison even when the binary contents are
/// byte-identical.
struct RemoteHelperFingerprint: Sendable, Equatable, Codable {
    let path: String
    let size: Int64
    let mtime: Date

    /// Reads the binary at `path` and produces a fingerprint. Returns
    /// `nil` for any soft-fail (missing file, unreadable attributes).
    /// Soft-fail mirrors `LaunchAgentInstaller.installedExecutablePath`
    /// — the upgrade path treats "no fingerprint" as "definitely
    /// reinstall", which is the safe direction.
    static func read(at path: String, fileManager: FileManager = .default) -> RemoteHelperFingerprint? {
        guard fileManager.fileExists(atPath: path) else { return nil }
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fileManager.attributesOfItem(atPath: path)
        } catch {
            // Non-critical: file vanished between fileExists and attribute
            // read, or attributes are unreadable. Returning nil makes the
            // reinstall path treat this as "no record" and rewrite cleanly.
            return nil
        }
        guard let size = attrs[.size] as? NSNumber,
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        return RemoteHelperFingerprint(path: path, size: size.int64Value, mtime: mtime)
    }
}

struct RemoteHelperHealth: Sendable, Equatable {
    let resolvedExecutablePath: String
    let resolvedExists: Bool
    let installedExecutablePath: String?
    /// `true` iff a plist is installed AND its `executablePath` matches
    /// the resolver's current path. `false` for "no plist installed" so
    /// callers don't have to special-case.
    let matchesInstalled: Bool
    /// `true` when there is no recorded last fingerprint (nothing to
    /// mismatch) OR when the recorded fingerprint matches the file
    /// currently at the resolved path. `false` only when both a record
    /// and a current file exist and they differ.
    let fingerprintMatchesLastInstall: Bool

    /// Composes a health snapshot from the three inputs (resolver,
    /// installer, optional last-known fingerprint). All file system
    /// reads happen here; callers can run this on any thread.
    static func inspect(
        resolver: any RemoteHelperPathResolving,
        installer: LaunchAgentInstaller,
        label: String,
        lastInstalledFingerprint: RemoteHelperFingerprint? = nil,
        fileManager: FileManager = .default
    ) -> RemoteHelperHealth {
        let resolvedURL = resolver.helperExecutableURL()
        let resolvedPath = resolvedURL.path
        let resolvedExists = fileManager.fileExists(atPath: resolvedPath)
        let installedPath = installer.installedExecutablePath(label: label)
        let matches = installedPath.map { $0 == resolvedPath } ?? false

        let fingerprintMatches: Bool = if let last = lastInstalledFingerprint {
            // Compare against whatever lives at the resolved path now.
            // If there is no file (resolvedExists == false), the binary
            // has gone missing under us — treat as a mismatch so the
            // reinstall path reasserts a coherent state.
            if let current = RemoteHelperFingerprint.read(at: resolvedPath, fileManager: fileManager) {
                current == last
            } else {
                false
            }
        } else {
            true
        }

        return RemoteHelperHealth(
            resolvedExecutablePath: resolvedPath,
            resolvedExists: resolvedExists,
            installedExecutablePath: installedPath,
            matchesInstalled: matches,
            fingerprintMatchesLastInstall: fingerprintMatches
        )
    }
}

// Installs and removes the `com.termura.remote-agent` LaunchAgent. The plist
// is rendered as XML data (no string-format hand-rolling) and persisted under
// `~/Library/LaunchAgents/` so launchd loads it for the current user only.
//
// The launchctl invocation is abstracted via `LaunchControlExecuting` so tests
// can run end-to-end in a temp directory without actually loading anything
// into launchd, and so the production path can be replaced if Apple deprecates
// the bootstrap subcommand.

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "LaunchAgentInstaller")

protocol LaunchControlExecuting: Sendable {
    func bootstrap(plistURL: URL) async throws
    func bootout(label: String) async throws
}

enum LaunchAgentError: Error, Sendable, Equatable {
    case plistEncodingFailed(reason: String)
    case launchctlFailed(reason: String)
    case fileWriteFailed(reason: String)
}

struct LaunchAgentInstaller: Sendable {
    struct PlistConfig: Sendable, Equatable {
        let label: String
        let executablePath: String
        /// Launchd will keep the agent running while it has work to do; we set
        /// `KeepAlive=false` so it idles out cleanly when no requests are in
        /// flight (silent push or main-app launch wakes it back up).
        let runAtLoad: Bool
        let standardOutPath: String?
        let standardErrPath: String?
        /// PR8 Phase 2 — names of mach services owned by this agent. The
        /// main app process opens an `NSXPCConnection(machServiceName:)`
        /// against each, and launchd demand-launches the agent on first
        /// connection. Empty by default to keep PR2/PR7 tests untouched.
        let machServices: [String]

        init(
            label: String,
            executablePath: String,
            runAtLoad: Bool = true,
            standardOutPath: String? = nil,
            standardErrPath: String? = nil,
            machServices: [String] = []
        ) {
            self.label = label
            self.executablePath = executablePath
            self.runAtLoad = runAtLoad
            self.standardOutPath = standardOutPath
            self.standardErrPath = standardErrPath
            self.machServices = machServices
        }
    }

    let baseDirectory: URL
    private let executor: any LaunchControlExecuting

    init(
        baseDirectory: URL = LaunchAgentInstaller.defaultDirectory,
        executor: any LaunchControlExecuting = LiveLaunchControlExecutor()
    ) {
        self.baseDirectory = baseDirectory
        self.executor = executor
    }

    /// Writes the plist and asks launchctl to load it. Idempotent: existing
    /// installations are bootouted-then-rebootstrapped so the on-disk plist
    /// always matches the supplied config.
    func install(_ config: PlistConfig) async throws {
        let plistURL = url(for: config.label)
        try ensureDirectoryExists()
        let data = try Self.renderPlistData(config: config)
        do {
            try data.write(to: plistURL, options: .atomic)
        } catch {
            throw LaunchAgentError.fileWriteFailed(reason: error.localizedDescription)
        }
        // Best-effort bootout in case the agent was previously loaded with
        // different settings. "Not loaded" is the common case on first install
        // and not actionable, so we log at debug level and continue.
        do {
            try await executor.bootout(label: config.label)
        } catch {
            logger.debug("bootout(\(config.label)) before install: \(error.localizedDescription)")
        }
        try await executor.bootstrap(plistURL: plistURL)
    }

    /// Removes the on-disk plist and asks launchctl to unload it. Idempotent;
    /// missing plist is treated as already-uninstalled.
    func uninstall(label: String) async throws {
        let plistURL = url(for: label)
        do {
            try await executor.bootout(label: label)
        } catch {
            logger.debug("bootout(\(label)) during uninstall: \(error.localizedDescription)")
        }
        do {
            try FileManager.default.removeItem(at: plistURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw LaunchAgentError.fileWriteFailed(reason: error.localizedDescription)
        }
    }

    func isInstalled(label: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: label).path)
    }

    /// Reads the on-disk plist for `label` and returns the first
    /// `ProgramArguments` entry. Returns `nil` for any soft-fail
    /// case — missing plist, unreadable plist, malformed XML, or a
    /// plist whose `ProgramArguments` is missing/empty/not a string
    /// array. PR10's `reinstallIfNeeded` uses this to detect that a
    /// previously installed plist points at a stale helper path.
    /// Soft-fail by design: a corrupt plist is treated as "no record"
    /// so the upgrade path can rewrite it cleanly instead of
    /// surfacing a launchctl-format error to the user.
    func installedExecutablePath(label: String) -> String? {
        let plistURL = url(for: label)
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: plistURL)
            let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
            guard let dict = raw as? [String: Any],
                  let args = dict["ProgramArguments"] as? [String],
                  let first = args.first else {
                return nil
            }
            return first
        } catch {
            // Non-critical: the on-disk plist is unreadable or malformed.
            // Returning nil lets reinstallIfNeeded rewrite it via the normal
            // install path; surfacing the IO error to UI here would be noise.
            logger.debug("installedExecutablePath(\(label)) read failed: \(error.localizedDescription)")
            return nil
        }
    }

    func url(for label: String) -> URL {
        baseDirectory.appendingPathComponent("\(label).plist")
    }

    private func ensureDirectoryExists() throws {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: baseDirectory.path, isDirectory: &isDir) {
            if isDir.boolValue { return }
            throw LaunchAgentError.fileWriteFailed(reason: "\(baseDirectory.path) exists but is not a directory")
        }
        do {
            try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        } catch {
            throw LaunchAgentError.fileWriteFailed(reason: error.localizedDescription)
        }
    }

    static func renderPlistData(config: PlistConfig) throws -> Data {
        var dict: [String: Any] = [
            "Label": config.label,
            "ProgramArguments": [config.executablePath],
            "RunAtLoad": config.runAtLoad,
            "KeepAlive": false,
            "LimitLoadToSessionType": "Aqua"
        ]
        if let stdout = config.standardOutPath {
            dict["StandardOutPath"] = stdout
        }
        if let stderr = config.standardErrPath {
            dict["StandardErrorPath"] = stderr
        }
        if !config.machServices.isEmpty {
            // Each entry maps `machServiceName -> true` so launchd
            // registers the named bootstrap service and routes incoming
            // NSXPC connections to the agent process.
            var services: [String: Bool] = [:]
            for name in config.machServices {
                services[name] = true
            }
            dict["MachServices"] = services
        }
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: dict,
                format: .xml,
                options: 0
            )
        } catch {
            throw LaunchAgentError.plistEncodingFailed(reason: error.localizedDescription)
        }
    }

    static var defaultDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/LaunchAgents")
    }
}

struct LiveLaunchControlExecutor: LaunchControlExecuting {
    func bootstrap(plistURL: URL) async throws {
        try await runLaunchctl(arguments: ["bootstrap", "gui/\(getuid())", plistURL.path])
    }

    func bootout(label: String) async throws {
        try await runLaunchctl(arguments: ["bootout", "gui/\(getuid())/\(label)"])
    }

    private func runLaunchctl(arguments: [String]) async throws {
        // WHY: launchctl is the only supported way to (re)load a per-user
        // LaunchAgent on modern macOS; bootstrap/bootout are short-lived.
        // OWNER: this method (synchronous lifetime — process is awaited inline)
        // CANCEL: launchctl exits on its own; not interruptible from caller
        // TEARDOWN: waitUntilExit() guarantees the child is reaped before return
        // TEST: Tests inject `LaunchControlExecuting` so this real path runs
        // only in integration / production builds.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw LaunchAgentError.launchctlFailed(reason: error.localizedDescription)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = stderr.fileHandleForReading.availableData
            let detail = String(data: data, encoding: .utf8) ?? "exit \(process.terminationStatus)"
            throw LaunchAgentError.launchctlFailed(reason: detail.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

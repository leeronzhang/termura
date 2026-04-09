import Foundation

/// Routes URLs detected in terminal output to internal views or external apps.
@MainActor
protocol LinkRouterProtocol: AnyObject, Sendable {
    /// Route a URL to the appropriate internal handler.
    /// Returns true if handled internally, false if opened externally.
    @discardableResult
    func route(url: URL, workingDirectory: String, forceExternal: Bool) -> Bool
}

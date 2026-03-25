import Foundation

/// Protocol abstracting context injection for restored terminal sessions.
protocol ContextInjectionServiceProtocol: Actor {
    func buildInjectionText(projectRoot: String) async -> String?
}

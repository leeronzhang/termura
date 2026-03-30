import Foundation

#if DEBUG

/// Test double for `ContextInjectionServiceProtocol`.
/// Supports error simulation via `stubbedError`.
actor MockContextInjectionService: ContextInjectionServiceProtocol {
    var stubbedInjectionText: String?
    /// When set, `buildInjectionText` returns nil (simulating failure).
    var stubbedError: (any Error)?
    var buildCallCount = 0
    var lastProjectRoot: String?

    func buildInjectionText(projectRoot: String) async -> String? {
        buildCallCount += 1
        lastProjectRoot = projectRoot
        if stubbedError != nil { return nil }
        return stubbedInjectionText
    }
}

#endif

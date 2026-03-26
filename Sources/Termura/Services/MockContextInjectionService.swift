import Foundation

/// Test double for `ContextInjectionServiceProtocol`.
actor MockContextInjectionService: ContextInjectionServiceProtocol {
    var stubbedInjectionText: String?
    var buildCallCount = 0
    var lastProjectRoot: String?

    func buildInjectionText(projectRoot: String) async -> String? {
        buildCallCount += 1
        lastProjectRoot = projectRoot
        return stubbedInjectionText
    }
}

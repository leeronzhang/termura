import Foundation
@testable import Termura

actor MockContextInjectionService: ContextInjectionServiceProtocol {
    var stubbedInjectionText: String?
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

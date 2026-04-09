import Foundation

#if DEBUG

/// Debug fallback for previews and local environment defaults.
actor DebugContextInjectionService: ContextInjectionServiceProtocol {
    var stubbedInjectionText: String?

    func buildInjectionText(projectRoot _: String) async -> String? {
        stubbedInjectionText
    }
}

#endif

import Foundation

#if DEBUG

/// Test double for `ThemeImportServiceProtocol` with call tracking.
/// Replaces the minimal inline `MockThemeImportService` struct in ThemeImportService.swift.
actor MockThemeImportServiceTracking: ThemeImportServiceProtocol {
    var stubbedDefinition: ThemeDefinition = .termuraDark
    var stubbedColors: ThemeColors = .dark
    var importJSONCallCount = 0
    var importItermCallCount = 0

    func importJSON(from url: URL) async throws -> ThemeDefinition {
        importJSONCallCount += 1
        return stubbedDefinition
    }

    func importItermColors(from url: URL) async throws -> ThemeDefinition {
        importItermCallCount += 1
        return stubbedDefinition
    }

    nonisolated func toThemeColors(_ definition: ThemeDefinition) -> ThemeColors {
        .dark
    }
}

#endif

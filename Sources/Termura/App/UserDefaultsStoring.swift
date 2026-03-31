import Foundation

/// Abstracts `UserDefaults` read/write operations for testability.
///
/// - Production: `UserDefaults.standard` is used automatically via default parameter values.
/// - Tests: inject `UserDefaults(suiteName: UUID().uuidString)!`; call
///   `removePersistentDomain(forName:)` in `tearDown` to prevent cross-test pollution.
/// - SwiftUI views: inject via `@Environment(\.userDefaults)`.
protocol UserDefaultsStoring: AnyObject {
    func set(_ value: Any?, forKey defaultName: String)
    func set(_ value: Bool, forKey defaultName: String)
    func set(_ value: Double, forKey defaultName: String)
    func string(forKey defaultName: String) -> String?
    func stringArray(forKey defaultName: String) -> [String]?
    func data(forKey defaultName: String) -> Data?
    func bool(forKey defaultName: String) -> Bool
    func double(forKey defaultName: String) -> Double
    func object(forKey defaultName: String) -> Any?
    func removeObject(forKey defaultName: String)
}

extension UserDefaults: UserDefaultsStoring {}

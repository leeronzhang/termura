import Foundation

enum GlobalEnvironmentDefaults {
    static let userDefaults: any UserDefaultsStoring = UserDefaults.standard
    static let notificationCenter: any NotificationCenterObserving = NotificationCenter.default
    static let fileManager: any FileManagerProtocol = FileManager.default
}

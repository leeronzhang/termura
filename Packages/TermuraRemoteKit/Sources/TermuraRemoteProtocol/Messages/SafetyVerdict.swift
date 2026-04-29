import Foundation

public enum SafetyVerdict: String, Sendable, Codable, Equatable, CaseIterable {
    case safe
    case requiresConfirmation = "requires_confirmation"
    case blocked
}

import CloudKit
import Foundation

/// Result of an iCloud account precheck. Surfaced to the SwiftUI settings
/// layer so the user can be told *why* remote control failed to start —
/// e.g. "you're not signed into iCloud" instead of a generic CloudKit error.
public enum ICloudAccountStatus: String, Sendable, Equatable {
    case available
    case noAccount
    case restricted
    case temporarilyUnavailable
    case couldNotDetermine
}

public enum ICloudAccountError: Error, Sendable, Equatable {
    case checkFailed(reason: String)
}

public protocol ICloudAccountChecker: Sendable {
    func currentStatus() async throws -> ICloudAccountStatus
}

/// Real-network implementation backed by `CKContainer.accountStatus()`.
public struct LiveICloudAccountChecker: ICloudAccountChecker {
    private let containerIdentifier: String

    public init(containerIdentifier: String = CloudKitSchema.containerIdentifier) {
        self.containerIdentifier = containerIdentifier
    }

    public func currentStatus() async throws -> ICloudAccountStatus {
        let container = CKContainer(identifier: containerIdentifier)
        let raw: CKAccountStatus
        do {
            raw = try await container.accountStatus()
        } catch {
            throw ICloudAccountError.checkFailed(reason: error.localizedDescription)
        }
        return Self.translate(raw)
    }

    static func translate(_ raw: CKAccountStatus) -> ICloudAccountStatus {
        switch raw {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .couldNotDetermine: return .couldNotDetermine
        @unknown default: return .couldNotDetermine
        }
    }
}

/// Test double — returns whatever you set in init, never touches the network.
public struct StaticICloudAccountChecker: ICloudAccountChecker {
    public let status: ICloudAccountStatus

    public init(status: ICloudAccountStatus) {
        self.status = status
    }

    public func currentStatus() async throws -> ICloudAccountStatus {
        status
    }
}

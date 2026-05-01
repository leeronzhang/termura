import CryptoKit
import Foundation

public struct PairingToken: Sendable, Codable, Equatable {
    public let value: String
    public let issuedAt: Date
    public let expiresAt: Date

    public init(value: String, issuedAt: Date, expiresAt: Date) {
        self.value = value
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
    }

    public func isValid(asOf now: Date) -> Bool {
        now >= issuedAt && now < expiresAt
    }
}

public struct PairingTokenIssuer: Sendable {
    public typealias Clock = @Sendable () -> Date
    public typealias RandomBytes = @Sendable (Int) -> Data

    private let clock: Clock
    private let randomBytes: RandomBytes
    private let lifetime: TimeInterval

    public init(
        lifetime: TimeInterval,
        clock: @escaping Clock = { Date() },
        randomBytes: @escaping RandomBytes = { Self.cryptoRandomBytes($0) }
    ) {
        self.lifetime = lifetime
        self.clock = clock
        self.randomBytes = randomBytes
    }

    public func issue() -> PairingToken {
        let now = clock()
        let bytes = randomBytes(32)
        let value = Self.base64URL(bytes)
        return PairingToken(value: value, issuedAt: now, expiresAt: now.addingTimeInterval(lifetime))
    }

    @Sendable
    public static func cryptoRandomBytes(_ count: Int) -> Data {
        let key = SymmetricKey(size: SymmetricKeySize(bitCount: count * 8))
        return key.withUnsafeBytes { Data($0) }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

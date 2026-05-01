import Foundation

public protocol RemoteCodec: Sendable {
    func encode(_ value: some Encodable) throws -> Data
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T
}

public struct JSONRemoteCodec: RemoteCodec {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        enc.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601Codec.string(from: date))
        }
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601Codec.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Date string \(raw) does not match expected ISO8601 format"
                )
            }
            return date
        }
        decoder = dec
    }

    public func encode(_ value: some Encodable) throws -> Data {
        try encoder.encode(value)
    }

    public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder.decode(type, from: data)
    }
}

public enum CodecError: Error, Sendable, Equatable {
    case payloadTooLarge(actual: Int, limit: Int)
    case unsupportedKind(String)
}

enum ISO8601Codec {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from raw: String) -> Date? {
        let primary = ISO8601DateFormatter()
        primary.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = primary.date(from: raw) {
            return date
        }
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: raw)
    }
}

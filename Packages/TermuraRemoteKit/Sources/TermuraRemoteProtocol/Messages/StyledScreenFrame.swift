import Foundation

/// A color carried on the wire for terminal cell styling. Either a 256-color
/// palette index or a 24-bit truecolor RGB triple. `nil` slots in `CellStyle`
/// mean "use the receiver's default" (which is theme-driven on the client).
///
/// Encoding is compact-keyed (`kind` + `value`) so the same form survives
/// JSON and MessagePack round-trips. RGB packs into a single 24-bit integer
/// to keep per-cell overhead small under the CloudKit 1 MB record budget.
public enum WireColor: Sendable, Equatable, Hashable {
    case palette(UInt8)
    case rgb(r: UInt8, g: UInt8, b: UInt8)
}

extension WireColor: Codable {
    private enum CodingKeys: String, CodingKey { case kind = "k", value = "v" }
    private enum Kind: String, Codable { case palette = "p", rgb = "r" }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .palette(index):
            try container.encode(Kind.palette, forKey: .kind)
            try container.encode(index, forKey: .value)
        case let .rgb(r, g, b):
            try container.encode(Kind.rgb, forKey: .kind)
            let packed = (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
            try container.encode(packed, forKey: .value)
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .palette:
            self = try .palette(container.decode(UInt8.self, forKey: .value))
        case .rgb:
            let packed = try container.decode(UInt32.self, forKey: .value)
            self = .rgb(
                r: UInt8(truncatingIfNeeded: packed >> 16),
                g: UInt8(truncatingIfNeeded: packed >> 8),
                b: UInt8(truncatingIfNeeded: packed)
            )
        }
    }
}

/// Visual style of a contiguous range of cells. Mirrors `GhosttyStyle` from
/// `vendor/ghostty/include/ghostty/vt/style.h` but in a wire-stable form.
///
/// `attrs` is a bitmask of `Attr` values; `underline` is one of the
/// `Underline` raw values. Both are encoded only when non-zero so the
/// default (un-styled) cell takes near-zero bytes after JSON/MessagePack
/// run-length encoding by `StyledRun`.
public struct CellStyle: Sendable, Equatable, Hashable {
    public let fg: WireColor?
    public let bg: WireColor?
    public let underlineColor: WireColor?
    public let attrs: UInt8
    public let underline: UInt8

    public static let `default` = CellStyle()

    public init(
        fg: WireColor? = nil,
        bg: WireColor? = nil,
        underlineColor: WireColor? = nil,
        attrs: UInt8 = 0,
        underline: UInt8 = 0
    ) {
        self.fg = fg
        self.bg = bg
        self.underlineColor = underlineColor
        self.attrs = attrs
        self.underline = underline
    }

    public enum Attr: UInt8, Sendable {
        case bold = 0b0000_0001
        case italic = 0b0000_0010
        case faint = 0b0000_0100
        case blink = 0b0000_1000
        case inverse = 0b0001_0000
        case invisible = 0b0010_0000
        case strikethrough = 0b0100_0000
        case overline = 0b1000_0000
    }

    public enum Underline: UInt8, Sendable {
        case none = 0, single = 1, double = 2, curly = 3, dotted = 4, dashed = 5
    }

    public func has(_ attr: Attr) -> Bool { (attrs & attr.rawValue) != 0 }
}

extension CellStyle: Codable {
    private enum CodingKeys: String, CodingKey {
        case fg, bg, underlineColor = "ul", attrs = "a", underline = "u"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fg = try container.decodeIfPresent(WireColor.self, forKey: .fg)
        bg = try container.decodeIfPresent(WireColor.self, forKey: .bg)
        underlineColor = try container.decodeIfPresent(WireColor.self, forKey: .underlineColor)
        attrs = try container.decodeIfPresent(UInt8.self, forKey: .attrs) ?? 0
        underline = try container.decodeIfPresent(UInt8.self, forKey: .underline) ?? 0
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fg, forKey: .fg)
        try container.encodeIfPresent(bg, forKey: .bg)
        try container.encodeIfPresent(underlineColor, forKey: .underlineColor)
        if attrs != 0 { try container.encode(attrs, forKey: .attrs) }
        if underline != 0 { try container.encode(underline, forKey: .underline) }
    }
}

/// One contiguous run of identically-styled cells. Producers must merge
/// adjacent same-style cells into one run (RLE) so wire size stays well
/// below CloudKit's per-record budget on typical 80×24 viewports.
public struct StyledRun: Sendable, Equatable, Hashable, Codable {
    public let text: String
    public let style: CellStyle

    public init(text: String, style: CellStyle) {
        self.text = text
        self.style = style
    }

    private enum CodingKeys: String, CodingKey { case text = "t", style = "s" }
}

/// One row of the rendered viewport, split into style-uniform runs.
/// Concatenating `runs.map(\.text)` reproduces the row's plain text form
/// (matching `ScreenFramePayload.lines[i]` modulo trailing-space trimming).
public struct StyledLine: Sendable, Equatable, Hashable, Codable {
    public let runs: [StyledRun]

    public init(runs: [StyledRun]) {
        self.runs = runs
    }

    private enum CodingKeys: String, CodingKey { case runs = "r" }
}

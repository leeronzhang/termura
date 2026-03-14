import AppKit
import SwiftTerm

// MARK: - SwiftTerm color conversion

extension ThemeColors {
    /// 16-color ANSI array for SwiftTerm's installColors().
    func toSwiftTermColors() -> [SwiftTerm.Color] {
        [
            black, red, green, yellow,
            blue, magenta, cyan, white,
            brightBlack, brightRed, brightGreen, brightYellow,
            brightBlue, brightMagenta, brightCyan, brightWhite
        ]
        .map { NSColor($0).toSwiftTermColor() }
    }
}

// MARK: - NSColor → SwiftTerm.Color

private extension NSColor {
    func toSwiftTermColor() -> SwiftTerm.Color {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return SwiftTerm.Color(red: 0, green: 0, blue: 0)
        }
        let r = UInt16(max(0, min(1, rgb.redComponent)) * 65535)
        let g = UInt16(max(0, min(1, rgb.greenComponent)) * 65535)
        let b = UInt16(max(0, min(1, rgb.blueComponent)) * 65535)
        return SwiftTerm.Color(red: r, green: g, blue: b)
    }
}

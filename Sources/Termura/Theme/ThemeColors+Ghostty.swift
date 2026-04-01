import AppKit
import SwiftUI

// MARK: - SwiftUI.Color → ghostty hex string

extension SwiftUI.Color {
    /// Returns a "#rrggbb" hex string for use in ghostty config files.
    var hexRGB: String {
        guard let rgb = NSColor(self).usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(max(0, min(1, rgb.redComponent)) * 255)
        let g = Int(max(0, min(1, rgb.greenComponent)) * 255)
        let b = Int(max(0, min(1, rgb.blueComponent)) * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

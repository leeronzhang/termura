import AppKit
import GhosttyKit

// MARK: - NSEvent → ghostty key / mods conversion

extension NSEvent {
    /// Build a ghostty key event from this NSEvent (without text field set).
    func makeGhosttyKey(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
        var key = ghostty_input_key_s()
        key.action = action
        key.keycode = UInt32(keyCode)
        key.mods = modifierFlags.ghosttyMods
        key.consumed_mods = modifierFlags.subtracting([.control, .command]).ghosttyMods
        key.text = nil
        key.composing = false
        if self.type == .keyDown || self.type == .keyUp,
           let chars = characters(byApplyingModifiers: []),
           let cp = chars.unicodeScalars.first {
            key.unshifted_codepoint = cp.value
        }
        return key
    }

    /// Text to encode for a keyDown event, omitting control characters ghostty handles itself.
    var ghosttyText: String? {
        guard let chars = characters else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return characters(byApplyingModifiers: modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700, scalar.value <= 0xF8FF { return nil }
        }
        return chars
    }
}

extension NSEvent.ModifierFlags {
    var ghosttyMods: ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if contains(.shift) { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if contains(.option) { mods |= GHOSTTY_MODS_ALT.rawValue }
        if contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(mods)
    }
}

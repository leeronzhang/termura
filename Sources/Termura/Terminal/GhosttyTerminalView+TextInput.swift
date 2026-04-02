import AppKit
import GhosttyKit

// MARK: - NSTextInputClient (IME / CJK composition support)

//
// All methods are `nonisolated` to satisfy the non-actor-isolated protocol
// from a @MainActor class (Swift 6 strict concurrency). AppKit always calls
// these on the main thread, so `MainActor.assumeIsolated` is safe.
//
// Non-Sendable parameters (`Any`, `NSAttributedString`) are converted to
// Sendable types (`String`) BEFORE entering the `assumeIsolated` closure
// to avoid "sending risks causing data races" errors.

extension GhosttyTerminalView: NSTextInputClient {
    nonisolated func hasMarkedText() -> Bool {
        MainActor.assumeIsolated {
            self.markedText.length > 0
        }
    }

    nonisolated func markedRange() -> NSRange {
        MainActor.assumeIsolated {
            guard self.markedText.length > 0 else { return NSRange() }
            return NSRange(location: 0, length: self.markedText.length)
        }
    }

    nonisolated func selectedRange() -> NSRange {
        MainActor.assumeIsolated {
            guard let surface = self.surface else { return NSRange() }
            var text = ghostty_text_s()
            guard ghostty_surface_read_selection(surface, &text) else { return NSRange() }
            defer { ghostty_surface_free_text(surface, &text) }
            return NSRange(location: Int(text.offset_start), length: Int(text.offset_len))
        }
    }

    nonisolated func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let content: String
        switch string {
        case let value as NSAttributedString: content = value.string
        case let value as String: content = value
        default: return
        }
        MainActor.assumeIsolated {
            self.markedText = NSMutableAttributedString(string: content)
            if self.keyTextAccumulator == nil {
                self.syncPreedit()
            }
        }
    }

    nonisolated func unmarkText() {
        MainActor.assumeIsolated {
            if self.markedText.length > 0 {
                self.markedText.mutableString.setString("")
                self.syncPreedit()
            }
        }
    }

    nonisolated func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    nonisolated func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        let text: String? = MainActor.assumeIsolated {
            guard let surface = self.surface, range.length > 0 else { return nil }
            var textBuf = ghostty_text_s()
            guard ghostty_surface_read_selection(surface, &textBuf) else { return nil }
            defer { ghostty_surface_free_text(surface, &textBuf) }
            return String(cString: textBuf.text)
        }
        guard let text else { return nil }
        return NSAttributedString(string: text)
    }

    nonisolated func characterIndex(for point: NSPoint) -> Int {
        0
    }

    nonisolated func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        MainActor.assumeIsolated {
            guard let surface = self.surface else {
                return NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 0, height: 0)
            }
            var xPos: Double = 0
            var yPos: Double = 0
            var width: Double = 0
            var height: Double = 0
            ghostty_surface_ime_point(surface, &xPos, &yPos, &width, &height)

            let viewRect = NSRect(x: xPos, y: self.frame.size.height - yPos, width: width, height: max(height, 1))
            let winRect = self.convert(viewRect, to: nil)
            guard let window = self.window else { return winRect }
            return window.convertToScreen(winRect)
        }
    }

    nonisolated func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        switch string {
        case let value as NSAttributedString: chars = value.string
        case let value as String: chars = value
        default: return
        }
        MainActor.assumeIsolated {
            guard NSApp.currentEvent != nil else { return }
            self.unmarkText()
            if var acc = self.keyTextAccumulator {
                acc.append(chars)
                self.keyTextAccumulator = acc
                return
            }
            guard let surface = self.surface else { return }
            let len = chars.utf8CString.count
            guard len > 1 else { return }
            chars.withCString { ptr in
                ghostty_surface_text(surface, ptr, UInt(len - 1))
            }
        }
    }

    /// Prevent NSBeep for unhandled selectors during IME composition.
    /// Empty body — no actor state access, so nonisolated override is safe.
    override nonisolated func doCommand(by selector: Selector) {}
}

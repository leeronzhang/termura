import AppKit
import GhosttyKit

// MARK: - Clipboard callbacks (called from ghostty threads via GhosttyCallbacks.swift)

extension GhosttyAppContext {
    // read_clipboard_cb: userdata = surface userdata (GhosttyTerminalView)
    // NSPasteboard must be accessed on the main thread. Read clipboard inside the
    // @MainActor Task to guarantee thread safety.
    nonisolated static func cReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        loc: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) -> Bool {
        guard let userdata else { return false }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        let stateInt = state.map { Int(bitPattern: $0) }
        Task { @MainActor [view, stateInt] in
            guard let surface = view.surface else { return }
            let str = NSPasteboard.general.string(forType: .string) ?? ""
            let statePtr: UnsafeMutableRawPointer? = stateInt.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
            str.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, statePtr, false)
            }
        }
        return false
    }

    // confirm_read_clipboard_cb: userdata = surface userdata
    nonisolated static func cConfirmReadClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        str: UnsafePointer<CChar>?,
        state: UnsafeMutableRawPointer?,
        req: ghostty_clipboard_request_e
    ) {
        guard let userdata, let str else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        let text = String(cString: str)
        let stateInt = state.map { Int(bitPattern: $0) }
        Task { @MainActor [view, text, stateInt] in
            guard let surface = view.surface else { return }
            let statePtr: UnsafeMutableRawPointer? = stateInt.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
            text.withCString { ptr in
                ghostty_surface_complete_clipboard_request(surface, ptr, statePtr, true)
            }
        }
    }

    // write_clipboard_cb: userdata = surface userdata
    nonisolated static func cWriteClipboard(
        _ userdata: UnsafeMutableRawPointer?,
        loc: ghostty_clipboard_e,
        content: UnsafePointer<ghostty_clipboard_content_s>?,
        len: Int,
        confirm: Bool
    ) {
        guard let content, len > 0 else { return }
        var texts: [String] = []
        for idx in 0 ..< len {
            let item = content[idx]
            guard let mime = item.mime,
                  String(cString: mime) == "text/plain",
                  let data = item.data else { continue }
            texts.append(String(cString: data))
        }
        guard let text = texts.first else { return }
        Task { @MainActor in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // close_surface_cb: userdata = surface userdata
    nonisolated static func cCloseSurface(
        _ userdata: UnsafeMutableRawPointer?,
        processAlive: Bool
    ) {
        guard let userdata else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(userdata).takeUnretainedValue()
        Task { @MainActor [view] in
            view.processDidExit(processAlive: processAlive)
        }
    }
}

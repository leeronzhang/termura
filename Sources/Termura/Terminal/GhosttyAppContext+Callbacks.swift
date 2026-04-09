import AppKit
import Foundation
import GhosttyKit

extension GhosttyAppContext {
    // MARK: - Static C Callbacks (nonisolated: called from ghostty threads)

    // Wakeup: userdata = app userdata (GhosttyAppContext).
    // Fires thousands of times/sec from IO thread — coalesced via scheduleTick().
    nonisolated static func cWakeup(_ userdata: UnsafeMutableRawPointer?) {
        guard let userdata else { return }
        let ctx = Unmanaged<GhosttyAppContext>.fromOpaque(userdata).takeUnretainedValue()
        ctx.scheduleTick()
    }

    // Action: routes UI actions to main actor.
    // ghostty's renderer thread manages its own draw loop via CVDisplayLink —
    // the macOS apprt does NOT handle GHOSTTY_ACTION_RENDER in the action callback.
    @discardableResult
    nonisolated static func cAction(
        _ app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        // Surface-targeted UI actions need the main actor.
        if target.tag == GHOSTTY_TARGET_SURFACE,
           let surface = target.target.surface {
            Task { @MainActor in
                Self.handleSurfaceAction(surface: surface, action: action)
            }
            return true
        }

        // App-targeted actions that Termura handles.
        switch action.tag {
        case GHOSTTY_ACTION_OPEN_URL:
            Task { @MainActor in
                Self.openURL(action.action.open_url)
            }
            return true
        default:
            return false
        }
    }

    @MainActor
    private static func handleSurfaceAction(surface: ghostty_surface_t, action: ghostty_action_s) {
        guard let ud = ghostty_surface_userdata(surface) else { return }
        let view = Unmanaged<GhosttyTerminalView>.fromOpaque(ud).takeUnretainedValue()

        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            guard let rawTitle = action.action.set_title.title,
                  let title = String(cString: rawTitle, encoding: .utf8) else { return }
            view.onTitleChanged?(title)

        case GHOSTTY_ACTION_PWD:
            guard let rawPwd = action.action.pwd.pwd else { return }
            view.onWorkingDirectoryChanged?(String(cString: rawPwd))

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            view.recordChildExitCode(action.action.child_exited.exit_code)

        case GHOSTTY_ACTION_COMMAND_FINISHED:
            view.onCommandFinished?(action.action.command_finished.exit_code)

        case GHOSTTY_ACTION_OPEN_URL:
            openURL(action.action.open_url)

        case GHOSTTY_ACTION_MOUSE_OVER_LINK:
            let link = action.action.mouse_over_link
            if link.len > 0, let ptr = link.url {
                let data = Data(bytes: ptr, count: Int(link.len))
                view.hoverUrl = String(data: data, encoding: .utf8)
            } else {
                view.hoverUrl = nil
            }

        default:
            break
        }
    }
}

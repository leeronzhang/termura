import Foundation

// VT submodule carries the render-state / cell / style API. It is split out
// from the top-level GhosttyKit module because vt/ enumerators collide with
// ghostty.h's own enums (e.g. GHOSTTY_COLOR_SCHEME_*) when both are seen in
// one translation unit; the sub-module gives clang a clean compilation
// boundary. Importing the sub-module pulls in parent-module symbols too
// (ghostty_surface_t, the wrapper, etc.), so a single import is enough.
import GhosttyKit.VT
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngineStyled")

extension LibghosttyEngine {
    /// Pull a styled snapshot of the visible viewport. Lazy-initialises the
    /// shared GhosttyRenderState / iterators on first call. Returns `nil`
    /// when the surface isn't attached, the C allocation chain failed, or
    /// the render-state update came back invalid — callers (the remote
    /// frame pulse) treat `nil` as "skip this tick" and fall back to the
    /// plain `readVisibleScreen()` text path.
    func readVisibleStyledScreen() -> TerminalStyledScreenSnapshot? {
        guard let surface = ghosttyView.surface else { return nil }
        if styledExtractor == nil {
            styledExtractor = StyledScreenExtractor()
        }
        return styledExtractor?.extract(surface: surface)
    }
}

/// Owns the C-side render-state resources for one LibghosttyEngine. The
/// init may fail (returning a "dud" extractor whose `extract` always returns
/// nil) so the caller can keep a single non-optional value and let the
/// fallback path engage transparently.
@MainActor
final class StyledScreenExtractor {
    // nonisolated(unsafe): deinit
    // C-side opaque pointers — immutable after init (written once, read
    // elsewhere) and must be freed from the implicit nonisolated deinit
    // per CLAUDE.md §4.4 / §4.7. Never reassigned, so the unsafe escape
    // from MainActor isolation has no concurrent-write risk.
    private nonisolated(unsafe) let renderState: GhosttyRenderState?
    private nonisolated(unsafe) let rowIterator: GhosttyRenderStateRowIterator?
    private nonisolated(unsafe) let rowCells: GhosttyRenderStateRowCells?

    init() {
        var state: GhosttyRenderState?
        let stateResult = ghostty_render_state_new(nil, &state)
        guard stateResult == GHOSTTY_SUCCESS, state != nil else {
            logger.error("ghostty_render_state_new failed: \(stateResult.rawValue)")
            renderState = nil
            rowIterator = nil
            rowCells = nil
            return
        }
        var iter: GhosttyRenderStateRowIterator?
        let iterResult = ghostty_render_state_row_iterator_new(nil, &iter)
        var cells: GhosttyRenderStateRowCells?
        let cellsResult = ghostty_render_state_row_cells_new(nil, &cells)
        guard iterResult == GHOSTTY_SUCCESS, iter != nil,
              cellsResult == GHOSTTY_SUCCESS, cells != nil
        else {
            logger.error("row iterator / cells alloc failed")
            ghostty_render_state_free(state)
            if let iter { ghostty_render_state_row_iterator_free(iter) }
            if let cells { ghostty_render_state_row_cells_free(cells) }
            renderState = nil
            rowIterator = nil
            rowCells = nil
            return
        }
        renderState = state
        rowIterator = iter
        rowCells = cells
    }

    deinit {
        if let renderState { ghostty_render_state_free(renderState) }
        if let rowIterator { ghostty_render_state_row_iterator_free(rowIterator) }
        if let rowCells { ghostty_render_state_row_cells_free(rowCells) }
    }

    /// Pull one styled snapshot. Caller passes the surface; the underlying
    /// C function locks the surface's renderer mutex internally for the
    /// duration of the update so the IO thread can't mutate the terminal
    /// state mid-walk.
    func extract(surface: ghostty_surface_t) -> TerminalStyledScreenSnapshot? {
        guard let renderState, let rowIterator, let rowCells else { return nil }

        // The wrapper's second argument is `void*` in C (see ghostty.h note)
        // because including vt/render.h there triggers enum-name collisions.
        // Cast the OpaquePointer back at the call site; ABI is identical.
        let renderStateRaw = UnsafeMutableRawPointer(renderState)
        let updateCode = ghostty_surface_render_state_update(surface, renderStateRaw)
        guard updateCode == 0 else { return nil }

        var cols: UInt16 = 0
        var rows: UInt16 = 0
        guard ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_COLS, &cols) == GHOSTTY_SUCCESS,
              ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROWS, &rows) == GHOSTTY_SUCCESS
        else { return nil }

        var iter: GhosttyRenderStateRowIterator? = rowIterator
        guard ghostty_render_state_get(renderState, GHOSTTY_RENDER_STATE_DATA_ROW_ITERATOR, &iter) == GHOSTTY_SUCCESS
        else { return nil }

        var styledLines: [StyledLine] = []
        var plainLines: [String] = []
        styledLines.reserveCapacity(Int(rows))
        plainLines.reserveCapacity(Int(rows))

        while ghostty_render_state_row_iterator_next(rowIterator) {
            var cellsHandle: GhosttyRenderStateRowCells? = rowCells
            guard ghostty_render_state_row_get(rowIterator, GHOSTTY_RENDER_STATE_ROW_DATA_CELLS, &cellsHandle) == GHOSTTY_SUCCESS
            else { continue }
            let (line, runs) = readRow(cells: rowCells, cols: Int(cols))
            styledLines.append(StyledLine(runs: runs))
            plainLines.append(line)
        }

        return TerminalStyledScreenSnapshot(
            rows: Int(rows), cols: Int(cols),
            lines: plainLines, styledLines: styledLines
        )
    }

    /// Walk one row's cells and emit RLE-merged style runs.
    /// `line` is the row's plain-text concatenation (used for the wire's
    /// `lines` fallback so older clients render identical text).
    private func readRow(
        cells: GhosttyRenderStateRowCells, cols: Int
    ) -> (line: String, runs: [StyledRun]) {
        var runs: [StyledRun] = []
        var currentText = ""
        var currentStyle = CellStyle.default
        var line = ""

        ghostty_render_state_row_cells_select(cells, 0)
        for x in 0 ..< cols {
            if x > 0 {
                guard ghostty_render_state_row_cells_next(cells) else { break }
            }
            var rawCell: GhosttyCell = 0
            let cellResult = ghostty_render_state_row_cells_get(
                cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_RAW, &rawCell
            )
            guard cellResult == GHOSTTY_SUCCESS else { continue }
            let glyph = readCellText(rawCell: rawCell)
            let style = readCellStyle(cells: cells, rawCell: rawCell)
            line.append(glyph)
            if style == currentStyle {
                currentText.append(glyph)
            } else {
                if !currentText.isEmpty {
                    runs.append(StyledRun(text: currentText, style: currentStyle))
                }
                currentText = glyph
                currentStyle = style
            }
        }
        if !currentText.isEmpty {
            runs.append(StyledRun(text: currentText, style: currentStyle))
        }
        return (line, runs)
    }

    /// Extract the visible glyph for a cell, falling back to a single space
    /// for empty / spacer-tail cells so the plain-text line stays
    /// column-aligned with the styled runs.
    private func readCellText(rawCell: GhosttyCell) -> String {
        var hasText = false
        _ = ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_HAS_TEXT, &hasText)
        if !hasText { return " " }
        var codepoint: UInt32 = 0
        guard ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_CODEPOINT, &codepoint) == GHOSTTY_SUCCESS,
              codepoint != 0,
              let scalar = Unicode.Scalar(codepoint)
        else { return " " }
        return String(scalar)
    }

    private func readCellStyle(
        cells: GhosttyRenderStateRowCells, rawCell: GhosttyCell
    ) -> CellStyle {
        var hasStyling = false
        _ = ghostty_cell_get(rawCell, GHOSTTY_CELL_DATA_HAS_STYLING, &hasStyling)
        if !hasStyling { return .default }
        var style = GhosttyStyle()
        style.size = MemoryLayout<GhosttyStyle>.size
        guard ghostty_render_state_row_cells_get(cells, GHOSTTY_RENDER_STATE_ROW_CELLS_DATA_STYLE, &style) == GHOSTTY_SUCCESS
        else { return .default }
        return CellStyle(
            fg: WireColor.from(ghostty: style.fg_color),
            bg: WireColor.from(ghostty: style.bg_color),
            underlineColor: WireColor.from(ghostty: style.underline_color),
            attrs: encodeAttrs(style),
            underline: UInt8(clamping: style.underline)
        )
    }

    private func encodeAttrs(_ style: GhosttyStyle) -> UInt8 {
        var attrs: UInt8 = 0
        if style.bold { attrs |= CellStyle.Attr.bold.rawValue }
        if style.italic { attrs |= CellStyle.Attr.italic.rawValue }
        if style.faint { attrs |= CellStyle.Attr.faint.rawValue }
        if style.blink { attrs |= CellStyle.Attr.blink.rawValue }
        if style.inverse { attrs |= CellStyle.Attr.inverse.rawValue }
        if style.invisible { attrs |= CellStyle.Attr.invisible.rawValue }
        if style.strikethrough { attrs |= CellStyle.Attr.strikethrough.rawValue }
        if style.overline { attrs |= CellStyle.Attr.overline.rawValue }
        return attrs
    }
}

private extension WireColor {
    static func from(ghostty color: GhosttyStyleColor) -> WireColor? {
        switch color.tag {
        case GHOSTTY_STYLE_COLOR_PALETTE:
            return .palette(UInt8(truncatingIfNeeded: color.value.palette))
        case GHOSTTY_STYLE_COLOR_RGB:
            let rgb = color.value.rgb
            return .rgb(r: rgb.r, g: rgb.g, b: rgb.b)
        default:
            return nil
        }
    }
}

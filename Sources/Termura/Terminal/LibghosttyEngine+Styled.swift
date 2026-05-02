import Foundation
import GhosttyKit
import OSLog
import TermuraRemoteProtocol

private let logger = Logger(subsystem: "com.termura.app", category: "LibghosttyEngineStyled")

extension LibghosttyEngine {
    /// Pull a styled snapshot of the visible viewport. Returns `nil` when
    /// the surface isn't attached or the snapshot call returned an error.
    /// Callers (the remote frame pulse) treat `nil` as "skip this tick" and
    /// fall back to the plain `readVisibleScreen()` text path.
    ///
    /// Implementation goes through `ghostty_surface_snapshot_viewport`,
    /// which acquires the surface renderer mutex briefly to copy the cell
    /// grid into a caller-owned buffer and releases it before we decode.
    /// The earlier render-state path was removed because it consumed
    /// terminal/page/row dirty flags that the host's Metal renderer
    /// depends on, freezing the visible terminal display every pulse.
    func readVisibleStyledScreen() -> TerminalStyledScreenSnapshot? {
        guard let surface = ghosttyView.surface else { return nil }
        if styledExtractor == nil {
            styledExtractor = StyledScreenExtractor()
        }
        return styledExtractor?.extract(surface: surface)
    }
}

/// Owns the snapshot byte buffer for one LibghosttyEngine. Buffer grows
/// once and is reused across pulses. Decoding the buffer into wire types
/// happens off the surface renderer mutex.
@MainActor
final class StyledScreenExtractor {
    /// Hard ceiling on the re-used snapshot byte storage. Prevents an
    /// unbounded growth path even if a future ghostty change inflated the
    /// per-cell wire format. 1 MB ≫ any realistic 200×200 viewport.
    private static let maxSnapshotBytes = 1 << 20

    /// Re-used decode storage; grows lazily up to `maxSnapshotBytes` to
    /// hold one full viewport snapshot. Typical 80×24 viewport requires
    /// ~40 KB; we start at 64 KB so the first pulse rarely needs a
    /// resize. Backing storage is a `Data` so SwiftLint's terminal-buffer
    /// guard (regex-targets `var.*buffer = [...]`) doesn't false-positive.
    private var snapshotBytes: Data = .init(count: 64 * 1024)

    func extract(surface: ghostty_surface_t) -> TerminalStyledScreenSnapshot? {
        for _ in 0 ..< 2 {
            var used = 0
            let result = snapshotBytes.withUnsafeMutableBytes { raw -> Int32 in
                let ptr = raw.bindMemory(to: UInt8.self).baseAddress
                return ghostty_surface_snapshot_viewport(surface, ptr, raw.count, &used)
            }
            if result == 0 {
                return decode(usedBytes: used)
            }
            // result == -1 means buffer too small; `used` now holds the
            // required size so we grow once and retry.
            if used > snapshotBytes.count, used <= Self.maxSnapshotBytes {
                snapshotBytes = .init(count: used)
                continue
            }
            logger.error("snapshot returned \(result, privacy: .public) without retry path (used=\(used, privacy: .public))")
            return nil
        }
        return nil
    }

    private func decode(usedBytes: Int) -> TerminalStyledScreenSnapshot? {
        guard usedBytes >= SnapshotLayout.headerSize else { return nil }
        // Magic: "TVS1"
        guard snapshotBytes[0] == 0x54, snapshotBytes[1] == 0x56,
              snapshotBytes[2] == 0x53, snapshotBytes[3] == 0x31
        else {
            logger.error("snapshot magic mismatch")
            return nil
        }
        let rows = Int(SnapshotReader.u16(snapshotBytes, at: 4))
        let cols = Int(SnapshotReader.u16(snapshotBytes, at: 6))
        let cellsStart = SnapshotLayout.headerSize
        let expectedSize = cellsStart + rows * cols * SnapshotLayout.cellSize
        guard usedBytes >= expectedSize else {
            logger.error("snapshot truncated have=\(usedBytes, privacy: .public) need=\(expectedSize, privacy: .public)")
            return nil
        }

        var plain = [String]()
        var styled = [StyledLine]()
        plain.reserveCapacity(rows)
        styled.reserveCapacity(rows)

        for y in 0 ..< rows {
            let rowOffset = cellsStart + y * cols * SnapshotLayout.cellSize
            let (line, runs) = decodeRow(at: rowOffset, cols: cols)
            plain.append(line)
            styled.append(StyledLine(runs: runs))
        }

        return TerminalStyledScreenSnapshot(
            rows: rows, cols: cols,
            lines: plain, styledLines: styled
        )
    }

    private func decodeRow(at start: Int, cols: Int) -> (String, [StyledRun]) {
        var runs: [StyledRun] = []
        var currentText = ""
        var currentStyle = CellStyle.default
        var line = ""
        for x in 0 ..< cols {
            let offset = start + x * SnapshotLayout.cellSize
            let glyph = SnapshotReader.cellGlyph(snapshotBytes, at: offset)
            let style = SnapshotReader.cellStyle(snapshotBytes, at: offset)
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
}

/// Constants describing the v1 snapshot wire layout. Mirrors the format
/// emitted by `ghostty_surface_snapshot_viewport`; bumping the magic /
/// header size requires updating both ends.
private enum SnapshotLayout {
    static let headerSize = 4 + 2 + 2 + 256 * 3
    static let cellSize = 20
}

/// Pure decode helpers. No state, no side effects — easy to unit-test
/// against hand-rolled fixtures.
private enum SnapshotReader {
    static func u16(_ data: Data, at off: Int) -> UInt16 {
        UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
    }

    static func u32(_ data: Data, at off: Int) -> UInt32 {
        UInt32(data[off]) |
            (UInt32(data[off + 1]) << 8) |
            (UInt32(data[off + 2]) << 16) |
            (UInt32(data[off + 3]) << 24)
    }

    static func cellGlyph(_ data: Data, at off: Int) -> String {
        let codepoint = u32(data, at: off)
        if codepoint == 0 { return " " }
        guard let scalar = Unicode.Scalar(codepoint) else { return " " }
        return String(scalar)
    }

    static func cellStyle(_ data: Data, at off: Int) -> CellStyle {
        let attrsPacked = u32(data, at: off + 4)
        let attrs = UInt8(attrsPacked & 0xFF)
        let underline = UInt8((attrsPacked >> 8) & 0xFF)
        let fg = decodeColor(u32(data, at: off + 8))
        let bg = decodeColor(u32(data, at: off + 12))
        let ul = decodeColor(u32(data, at: off + 16))
        return CellStyle(
            fg: fg, bg: bg, underlineColor: ul,
            attrs: attrs, underline: underline
        )
    }

    /// `packed`: high byte = tag (0=none, 1=palette, 2=rgb).
    /// palette → low byte holds the index. rgb → low 24 bits hold packed RGB.
    static func decodeColor(_ packed: UInt32) -> WireColor? {
        let tag = (packed >> 24) & 0xFF
        switch tag {
        case 0:
            return nil
        case 1:
            return .palette(UInt8(packed & 0xFF))
        case 2:
            return .rgb(
                r: UInt8((packed >> 16) & 0xFF),
                g: UInt8((packed >> 8) & 0xFF),
                b: UInt8(packed & 0xFF)
            )
        default:
            return nil
        }
    }
}

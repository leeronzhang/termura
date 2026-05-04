// Tool-input summarisation for the iOS conversation view. The summary's
// **first line** is the collapsed-state hint (single-line preview); any
// subsequent lines surface in the expanded state. Mutating / file-write
// tools (`Write`, `Edit`, `MultiEdit`) embed a truncated code preview
// here so iOS can render the same body Claude Code shows in its
// terminal — without that, the iOS row only sees the file path and the
// actual change is invisible.

import Foundation

extension ClaudeCodeTranscriptParser {
    /// Hard cap on the embedded code preview so a single 100-line Write
    /// can't blow past CK envelope budgets. ~2000 chars ≈ 50 lines of
    /// dense code, enough to read the change without scrolling forever.
    static let toolPreviewByteCap = 2000

    func summarize(name: String, input: [String: TranscriptAnyJSON]?) -> String {
        guard let input else { return "" }
        switch name {
        case "Write":
            return writeSummary(input: input)
        case "Edit", "MultiEdit":
            return editSummary(input: input)
        default:
            break
        }
        if case let .string(value) = input["command"] { return value }
        if case let .string(value) = input["file_path"] { return value }
        if case let .string(value) = input["path"] { return value }
        if case let .string(value) = input["pattern"] { return value }
        // Fallback: compact JSON, capped so a 10 KB tool input doesn't
        // pollute the wire. JSONEncoder failure here is non-actionable
        // (the input was already JSON-decoded above), so fall through
        // to "" rather than propagate.
        let data: Data
        do {
            data = try JSONEncoder().encode(input)
        } catch {
            return ""
        }
        guard let text = String(data: data, encoding: .utf8) else { return "" }
        return String(text.prefix(120))
    }

    private func writeSummary(input: [String: TranscriptAnyJSON]) -> String {
        let path = stringValue(input["file_path"]) ?? stringValue(input["path"]) ?? ""
        let content = stringValue(input["content"]) ?? ""
        let total = lineCount(of: content)
        let header = "\(path) — wrote \(total) line\(total == 1 ? "" : "s")"
        return Self.previewBody(header: header, body: content)
    }

    private func editSummary(input: [String: TranscriptAnyJSON]) -> String {
        let path = stringValue(input["file_path"]) ?? stringValue(input["path"]) ?? ""
        let newText = stringValue(input["new_string"]) ?? joinedMultiEditNewStrings(input["edits"]) ?? ""
        let oldText = stringValue(input["old_string"]) ?? ""
        let added = lineCount(of: newText)
        let removed = lineCount(of: oldText)
        let header = "\(path) — +\(added) / −\(removed) line\(added == 1 && removed == 1 ? "" : "s")"
        return Self.previewBody(header: header, body: newText)
    }

    /// Concat all `edits[].new_string` slices for the `MultiEdit` tool
    /// (Claude Code may issue several patches in one tool call). Returns
    /// nil when the field is absent or doesn't decode as expected so the
    /// caller falls back to the empty string rather than spurious "0".
    private func joinedMultiEditNewStrings(_ raw: TranscriptAnyJSON?) -> String? {
        guard case let .array(items) = raw else { return nil }
        let strings: [String] = items.compactMap { item in
            guard case let .object(fields) = item else { return nil }
            return stringValue(fields["new_string"])
        }
        return strings.isEmpty ? nil : strings.joined(separator: "\n")
    }

    private static func previewBody(header: String, body: String) -> String {
        guard !body.isEmpty else { return header }
        let snippet = String(body.prefix(toolPreviewByteCap))
        let truncated = snippet.count < body.count
        let suffix = truncated ? "\n…\(body.count - snippet.count) more chars" : ""
        return "\(header)\n\n\(snippet)\(suffix)"
    }

    private func stringValue(_ value: TranscriptAnyJSON?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text
    }

    private func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: "\n").count
    }
}

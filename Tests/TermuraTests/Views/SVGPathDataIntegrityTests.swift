import SwiftUI
@testable import Termura
import Testing

/// Regression suite for the `+`-concatenated SVG path literals in
/// `AgentSVGPathData.swift`. Swift's compile-time literal folding is bare
/// concatenation: a missing leading space on a continuation line silently
/// merges two coordinates into one (`"L10" + "15.06"` → `"L1015.06"`). The
/// numeric parser may accept the merged form as a valid huge X coordinate,
/// drawing strokes hundreds of points outside the icon's frame.
///
/// These tests fail loudly the next time someone re-chunks the path strings
/// without preserving whitespace at every boundary.
@Suite("AgentSVGPathData integrity")
struct SVGPathDataIntegrityTests {
    @Test("Claude path parses to a bounding rect inside the icon frame")
    func claudePathStaysInsideIconFrame() {
        assertPathBoundsInsideFrame(agentSVGClaudePath, label: "claude")
    }

    @Test("OpenAI path parses to a bounding rect inside the icon frame")
    func openAIPathStaysInsideIconFrame() {
        assertPathBoundsInsideFrame(agentSVGOpenAIPath, label: "openai")
    }

    @Test("Gemini path parses to a bounding rect inside the icon frame")
    func geminiPathStaysInsideIconFrame() {
        assertPathBoundsInsideFrame(agentSVGGeminiPath, label: "gemini")
    }

    @Test("Every numeric token in every path parses as Double")
    func everyNumericTokenIsValid() {
        for (label, source) in pathSources() {
            let tokens = tokenize(source)
            for token in tokens where !token.isCommandLetter {
                let parsed = Double(token)
                // Swift Testing's `#expect` second argument is `Comment?`,
                // which only accepts a single string literal — runtime
                // `String + String` does not auto-convert. Keep the
                // message in one interpolated literal.
                #expect(
                    parsed != nil,
                    "[\(label)] non-numeric token survived parsing: '\(token)'. This usually means a `+` continuation literal lost its leading space."
                )
            }
        }
    }

    // MARK: - Helpers

    private func pathSources() -> [(String, String)] {
        [
            ("claude", agentSVGClaudePath),
            ("openai", agentSVGOpenAIPath),
            ("gemini", agentSVGGeminiPath)
        ]
    }

    private func assertPathBoundsInsideFrame(_ source: String, label: String) {
        let frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        let path = SVGPathShape(svgPath: source, viewBox: 24).path(in: frame)
        let bounds = path.boundingRect
        let tolerance: CGFloat = 0.5
        let allowed = frame.insetBy(dx: -tolerance, dy: -tolerance)
        #expect(
            allowed.contains(bounds),
            "[\(label)] path bounds \(bounds) escape icon frame \(frame). A coordinate parsed >> viewBox usually means a `+` continuation literal merged two numbers."
        )
    }

    private func tokenize(_ source: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for ch in source {
            if ch.isLetter, ch != "e" {
                if !current.isEmpty {
                    tokens.append(current); current = ""
                }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," || ch == "\n" {
                if !current.isEmpty {
                    tokens.append(current); current = ""
                }
            } else if ch == "-", !current.isEmpty {
                tokens.append(current); current = String(ch)
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}

private extension String {
    var isCommandLetter: Bool {
        count == 1 && first?.isLetter == true && first != "e"
    }
}

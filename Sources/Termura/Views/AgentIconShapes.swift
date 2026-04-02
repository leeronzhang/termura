import SwiftUI

// MARK: - SVG path data from RemixIcon (Apache 2.0), viewBox 0 0 24 24

// Path string data lives in AgentSVGPathData.swift (excluded from line_length linting).

enum AgentSVGPaths {
    /// ri-claude-fill
    static let claude = agentSVGClaudePath
    /// ri-openai-fill
    static let openai = agentSVGOpenAIPath
    /// ri-gemini-fill
    static let gemini = agentSVGGeminiPath
    /// Generic ">_" prompt
    static let generic = "M4 6L10 12L4 18M12 18H20"
}

// MARK: - Shape wrappers

struct ClaudeIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathShape(svgPath: AgentSVGPaths.claude, viewBox: 24).path(in: rect)
    }
}

struct OpenAIIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathShape(svgPath: AgentSVGPaths.openai, viewBox: 24).path(in: rect)
    }
}

struct GeminiIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathShape(svgPath: AgentSVGPaths.gemini, viewBox: 24).path(in: rect)
    }
}

struct GenericAgentIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathShape(svgPath: AgentSVGPaths.generic, viewBox: 24).path(in: rect)
    }
}

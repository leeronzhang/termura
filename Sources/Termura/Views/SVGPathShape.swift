import SwiftUI

// MARK: - Minimal SVG path parser (M, L, C, H, V, Z + lowercase relative)

struct SVGPathShape: Shape {
    let svgPath: String
    let viewBox: CGFloat

    func path(in rect: CGRect) -> Path {
        var ctx = SVGParseContext(rect: rect, viewBox: viewBox)
        ctx.parse(svgPath)
        return ctx.result
    }
}

// MARK: - Parser context (groups mutable state to keep function signatures lean)

private struct SVGParseContext {
    var result = Path()
    var cursor = CGPoint.zero
    var subpathStart = CGPoint.zero

    let scale: CGFloat
    let origin: CGPoint
    private var tokens: [String] = []
    private var index = 0

    init(rect: CGRect, viewBox: CGFloat) {
        scale = min(rect.width, rect.height) / viewBox
        origin = CGPoint(
            x: rect.midX - (viewBox * scale) / 2,
            y: rect.midY - (viewBox * scale) / 2
        )
    }

    // MARK: - Main parse loop

    mutating func parse(_ pathData: String) {
        tokens = Self.tokenize(pathData)
        index = 0
        while index < tokens.count {
            let command = tokens[index]; index += 1
            switch command {
            case "M": handleMoveTo()
            case "m": handleRelativeMoveTo()
            case "L": handleLineTo()
            case "l": handleRelativeLineTo()
            case "H": handleHorizontal()
            case "h": handleRelativeHorizontal()
            case "V": handleVertical()
            case "v": handleRelativeVertical()
            case "C": handleCubic()
            case "c": handleRelativeCubic()
            case "Z", "z": result.closeSubpath(); cursor = subpathStart
            default: break
            }
        }
    }

    // MARK: - Helpers

    private mutating func nextNumber() -> CGFloat {
        guard index < tokens.count,
              let value = Double(tokens[index]) else { return 0 }
        index += 1
        return CGFloat(value)
    }

    private func absolute(_ xVal: CGFloat, _ yVal: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + xVal * scale, y: origin.y + yVal * scale)
    }

    private var hasMoreNumbers: Bool {
        index < tokens.count && Double(tokens[index]) != nil
    }

    // MARK: - Command handlers

    private mutating func handleMoveTo() {
        let dest = absolute(nextNumber(), nextNumber())
        result.move(to: dest); cursor = dest; subpathStart = dest
        while hasMoreNumbers {
            let lineDest = absolute(nextNumber(), nextNumber())
            result.addLine(to: lineDest); cursor = lineDest
        }
    }

    private mutating func handleRelativeMoveTo() {
        let dest = CGPoint(
            x: cursor.x + nextNumber() * scale,
            y: cursor.y + nextNumber() * scale
        )
        result.move(to: dest); cursor = dest; subpathStart = dest
    }

    private mutating func handleLineTo() {
        while hasMoreNumbers {
            let dest = absolute(nextNumber(), nextNumber())
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleRelativeLineTo() {
        while hasMoreNumbers {
            let dest = CGPoint(
                x: cursor.x + nextNumber() * scale,
                y: cursor.y + nextNumber() * scale
            )
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleHorizontal() {
        while hasMoreNumbers {
            let dest = CGPoint(x: origin.x + nextNumber() * scale, y: cursor.y)
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleRelativeHorizontal() {
        while hasMoreNumbers {
            let dest = CGPoint(x: cursor.x + nextNumber() * scale, y: cursor.y)
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleVertical() {
        while hasMoreNumbers {
            let dest = CGPoint(x: cursor.x, y: origin.y + nextNumber() * scale)
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleRelativeVertical() {
        while hasMoreNumbers {
            let dest = CGPoint(x: cursor.x, y: cursor.y + nextNumber() * scale)
            result.addLine(to: dest); cursor = dest
        }
    }

    private mutating func handleCubic() {
        while hasMoreNumbers {
            let ctrl1 = absolute(nextNumber(), nextNumber())
            let ctrl2 = absolute(nextNumber(), nextNumber())
            let end = absolute(nextNumber(), nextNumber())
            result.addCurve(to: end, control1: ctrl1, control2: ctrl2)
            cursor = end
        }
    }

    private mutating func handleRelativeCubic() {
        while hasMoreNumbers {
            let ax = nextNumber(), ay = nextNumber()
            let bx = nextNumber(), by = nextNumber()
            let ex = nextNumber(), ey = nextNumber()
            let ctrl1 = CGPoint(x: cursor.x + ax * scale, y: cursor.y + ay * scale)
            let ctrl2 = CGPoint(x: cursor.x + bx * scale, y: cursor.y + by * scale)
            let end = CGPoint(x: cursor.x + ex * scale, y: cursor.y + ey * scale)
            result.addCurve(to: end, control1: ctrl1, control2: ctrl2)
            cursor = end
        }
    }

    // MARK: - Tokenizer

    private static func tokenize(_ pathData: String) -> [String] {
        var tokens: [String] = []
        var number = ""
        var prevChar: Character = " "
        func flush() { if !number.isEmpty { tokens.append(number); number = "" } }
        for ch in pathData {
            if ch.isLetter, ch != "e" {
                flush(); tokens.append(String(ch))
            } else if ch == "," || ch == " " || ch == "\n" {
                flush()
            } else if ch == "-", !number.isEmpty, prevChar != "e" {
                flush(); number.append(ch)
            } else {
                number.append(ch)
            }
            prevChar = ch
        }
        flush()
        return tokens
    }
}

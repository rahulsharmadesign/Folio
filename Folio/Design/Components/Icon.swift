import SwiftUI

/// The thin-stroke icons from the design source, drawn from their SVG path data (viewBox 0 0 24 24).
enum FolioIcon: String, CaseIterable, Sendable {
    case today, library, notebook, schedule, appearance
    case arrowRight, chevronLeft, chevronRight, chevronDown, check, resurface, menu, highlight, bookmark, plus

    /// Path data copied verbatim from design/source/*.dc.html.
    var paths: [String] {
        switch self {
        case .today: ["M4 18h16", "M7 18a5 5 0 0 1 10 0", "M12 5v3", "M5.6 10.6l1.5 1.2", "M18.4 10.6l-1.5 1.2"]
        case .library: ["M3 5.5c2.6-1 5.6-1 9 1 3.4-2 6.4-2 9-1v13c-2.6-1-5.6-1-9 1-3.4-2-6.4-2-9-1z", "M12 6.5v13"]
        case .notebook: ["M6 3.5h11.5a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H6z", "M9 3.5v17", "M12 8.5h3.5", "M12 11.5h3.5"]
        case .schedule: ["M12 7.5V12l3 2"]
        case .appearance: ["M12 3.5s6 6.4 6 10.8a6 6 0 0 1-12 0C6 9.9 12 3.5 12 3.5z", "M9.2 14.6a2.9 2.9 0 0 0 2.6 2.7"]
        case .arrowRight: ["M5 12h14", "M13 6l6 6-6 6"]
        case .chevronLeft: ["M15 6l-6 6 6 6"]
        case .chevronRight: ["M9 6l6 6-6 6"]
        case .chevronDown: ["M6 9l6 6 6-6"]
        case .check: ["M5 12.5l4.5 4.5L19 7.5"]
        case .resurface: ["M20 12a8 8 0 1 1-2.3-5.6", "M20 4v4.5h-4.5"]
        case .menu: ["M4 7h16", "M4 12h16", "M4 17h10"]
        case .highlight: ["M14.5 4.5l5 5L10 19H5v-5z", "M4 21h16"]
        case .bookmark: ["M6.5 3.5h11v17l-5.5-4-5.5 4z"]
        case .plus: ["M12 5v14", "M5 12h14"]
        }
    }

    /// `<circle cx cy r>` elements.
    var circles: [(x: CGFloat, y: CGFloat, r: CGFloat)] {
        switch self {
        case .schedule: [(12, 12, 8.5)]
        default: []
        }
    }

    /// The icon in 24-unit space.
    var path: Path {
        var p = Path()
        for d in paths { p.addPath(SVGPath.parse(d)) }
        for c in circles { p.addEllipse(in: CGRect(x: c.x - c.r, y: c.y - c.r, width: 2 * c.r, height: 2 * c.r)) }
        return p
    }
}

/// An icon stroked like the SVG: `stroke-width` in viewBox units, round caps and joins.
struct IconView: View {
    let icon: FolioIcon
    var size: CGFloat = 18
    var strokeWidth: CGFloat = 1.5

    var body: some View {
        IconShape(icon: icon)
            .stroke(style: StrokeStyle(lineWidth: strokeWidth * size / 24, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct IconShape: Shape {
    let icon: FolioIcon

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        return icon.path.applying(CGAffineTransform(scaleX: s, y: s).translatedBy(x: rect.minX / s, y: rect.minY / s))
    }
}

// MARK: - SVG path data

/// A small SVG path-data parser: M L H V C S A Z (absolute and relative), with implicit repeats.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var scanner = Tokenizer(d)
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var command: Character = "M"

        while let token = scanner.nextCommandOrNumber() {
            if case .command(let c) = token { command = c } else { scanner.pushBack() }
            let relative = command.isLowercase
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            switch command.lowercased().first! {
            case "m":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = pt(x, y); start = current
                path.move(to: current)
                command = relative ? "l" : "L" // Further pairs are line-tos.
                lastControl = nil
            case "l":
                guard let x = scanner.number(), let y = scanner.number() else { return path }
                current = pt(x, y); path.addLine(to: current); lastControl = nil
            case "h":
                guard let x = scanner.number() else { return path }
                current = CGPoint(x: relative ? current.x + x : x, y: current.y); path.addLine(to: current); lastControl = nil
            case "v":
                guard let y = scanner.number() else { return path }
                current = CGPoint(x: current.x, y: relative ? current.y + y : y); path.addLine(to: current); lastControl = nil
            case "c":
                guard let x1 = scanner.number(), let y1 = scanner.number(), let x2 = scanner.number(),
                      let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = pt(x1, y1), c2 = pt(x2, y2), end = pt(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "s":
                guard let x2 = scanner.number(), let y2 = scanner.number(), let x = scanner.number(), let y = scanner.number() else { return path }
                let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                let c2 = pt(x2, y2), end = pt(x, y)
                path.addCurve(to: end, control1: c1, control2: c2)
                lastControl = c2; current = end
            case "a":
                guard let rx = scanner.number(), let ry = scanner.number(), let rot = scanner.number(),
                      let large = scanner.number(), let sweep = scanner.number(),
                      let x = scanner.number(), let y = scanner.number() else { return path }
                let end = pt(x, y)
                addArc(to: &path, from: current, to: end, rx: rx, ry: ry, rotation: rot, largeArc: large != 0, sweep: sweep != 0)
                current = end; lastControl = nil
            case "z":
                path.closeSubpath(); current = start; lastControl = nil
            default:
                return path
            }
        }
        return path
    }

    /// SVG endpoint arc → cubic Béziers (SVG 1.1 implementation notes, F.6.5).
    private static func addArc(to path: inout Path, from p0: CGPoint, to p1: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat,
                               rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        var rx = abs(rx0), ry = abs(ry0)
        guard rx > 0, ry > 0, p0 != p1 else { path.addLine(to: p1); return }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 { rx *= sqrt(lambda); ry *= sqrt(lambda) }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }

        let segments = Int(ceil(abs(delta) / (.pi / 2)))
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        func point(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi,
                    y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi,
                    y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta1
        for i in 0..<segments {
            let t2 = t + step
            let a = point(t), b = i == segments - 1 ? p1 : point(t2)
            let da = derivative(t), db = derivative(t2)
            path.addCurve(to: b,
                          control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                          control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t = t2
        }
    }

    private enum Token { case command(Character), number(CGFloat) }

    private struct Tokenizer {
        private let chars: [Character]
        private var index = 0
        private var previous = 0

        init(_ s: String) { chars = Array(s) }

        mutating func pushBack() { index = previous }

        mutating func nextCommandOrNumber() -> Token? {
            skipSeparators()
            previous = index
            guard index < chars.count else { return nil }
            let c = chars[index]
            if c.isLetter, c != "e", c != "E" { index += 1; return .command(c) }
            return number().map { .number($0) }
        }

        mutating func number() -> CGFloat? {
            skipSeparators()
            let begin = index
            var seenDot = false, seenExp = false
            if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
            while index < chars.count {
                let c = chars[index]
                if c.isNumber { index += 1 }
                else if c == ".", !seenDot, !seenExp { seenDot = true; index += 1 }
                else if c == "e" || c == "E", !seenExp {
                    seenExp = true; index += 1
                    if index < chars.count, chars[index] == "-" || chars[index] == "+" { index += 1 }
                } else { break }
            }
            guard index > begin, let value = Double(String(chars[begin..<index])) else { index = begin; return nil }
            return CGFloat(value)
        }

        private mutating func skipSeparators() {
            while index < chars.count, chars[index] == " " || chars[index] == "," || chars[index].isNewline { index += 1 }
        }
    }
}

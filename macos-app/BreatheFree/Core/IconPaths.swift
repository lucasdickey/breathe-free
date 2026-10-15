//
//  IconPaths.swift
//  BreatheFree
//
//  The settings fan's icons, from the same path data as the browser version's and the Android
//  app's: line icons on a 24-unit grid, written in SVG's path language and read here into
//  moves, lines and cubic curves for SwiftUI to stroke.
//

import Foundation

/// One step along a path.
enum PathPiece: Equatable {
    case move(SIMD2<Double>)
    case line(SIMD2<Double>)
    case curve(SIMD2<Double>, SIMD2<Double>, SIMD2<Double>)
    case close
}

/// The settings fan's icons.
enum FanIcons {
    /// Waves for Ambient, a bell for Bells, and the speaker crossed out for Silent.
    static func sound(_ mode: SoundMode) -> [PathPiece] {
        switch mode {
        case .ambient: return ambient
        case .bells: return bells
        case .silent: return silent
        }
    }

    private static let ambient = IconPath.read(
        "M3 9c1.5-2 3-2 4.5 0s3 2 4.5 0 3-2 4.5 0 3 2 4.5 0M3 15c1.5-2 3-2 4.5 0s3 2 4.5 0 3-2 4.5 0 3 2 4.5 0")
    private static let bells = IconPath.read("M6.5 16v-5a5.5 5.5 0 0 1 11 0v5l1.5 2h-14zM10.2 20.6a2 2 0 0 0 3.6 0")
    private static let silent = IconPath.read("M3 9h4l5-4.5v15L7 15H3zM15.5 9.5l5 5M20.5 9.5l-5 5")

    /// A head speaking, or with a cross where its words would be, as the silent speaker.
    private static let head = "M5.5 8.5a3.5 3.5 0 1 0 7 0a3.5 3.5 0 1 0-7 0zM3 20c0-3.4 2.7-5.5 6-5.5s6 2.1 6 5.5"
    static let voiceOn = IconPath.read(head + "M16 6.2a4 4 0 0 1 0 5.6M18.8 3.6a7.6 7.6 0 0 1 0 10.8")
    static let voiceOff = IconPath.read(head + "M16 6.5l4.5 4.5M20.5 6.5L16 11")
}

/// Reads SVG path data: M, L, H, V, C, S, A and Z, absolute or relative, numbers without
/// exponents. Arcs come out as cubic curves, a quarter turn at most each.
enum IconPath {
    static func read(_ data: String) -> [PathPiece] {
        var text = PathText(data)
        var pieces: [PathPiece] = []
        var command: Character = "M"
        var at = SIMD2<Double>(0, 0), start = at
        // The second control point of the curve just drawn, for S to mirror.
        var lastControl: SIMD2<Double>?
        while !text.atEnd {
            if let c = text.command() {
                command = c
            } else if command == "Z" || command == "z" {
                return pieces // numbers after a close: not a path
            }
            let base = command.isLowercase ? at : SIMD2<Double>(0, 0)
            func point() -> SIMD2<Double>? {
                guard let x = text.number(), let y = text.number() else { return nil }
                return base + SIMD2(x, y)
            }
            switch command.uppercased() {
            case "M":
                guard let p = point() else { return pieces }
                pieces.append(.move(p))
                at = p
                start = p
                lastControl = nil
                // Further pairs after a move are lines.
                command = command.isLowercase ? "l" : "L"
            case "L":
                guard let p = point() else { return pieces }
                pieces.append(.line(p))
                at = p
                lastControl = nil
            case "H":
                guard let x = text.number() else { return pieces }
                at = SIMD2(base.x + x, at.y)
                pieces.append(.line(at))
                lastControl = nil
            case "V":
                guard let y = text.number() else { return pieces }
                at = SIMD2(at.x, base.y + y)
                pieces.append(.line(at))
                lastControl = nil
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return pieces }
                pieces.append(.curve(c1, c2, p))
                at = p
                lastControl = c2
            case "S":
                // Its first control point mirrors the last curve's second, about where it ended.
                let c1 = lastControl.map { 2 * at - $0 } ?? at
                guard let c2 = point(), let p = point() else { return pieces }
                pieces.append(.curve(c1, c2, p))
                at = p
                lastControl = c2
            case "A":
                guard let rx = text.number(), let ry = text.number(), let turn = text.number(),
                      let large = text.number(), let sweep = text.number(), let p = point() else { return pieces }
                pieces += arc(from: at, to: p, radii: SIMD2(abs(rx), abs(ry)), turn: turn * .pi / 180,
                              large: large != 0, sweep: sweep != 0)
                at = p
                lastControl = nil
            case "Z":
                pieces.append(.close)
                at = start
                lastControl = nil
            default:
                return pieces
            }
        }
        return pieces
    }

    /// An elliptical arc from `p1` to `p2` as SVG draws it (its ellipse turned by `turn`, the
    /// large or small way round, clockwise on screen if `sweep`), as cubic curves.
    static func arc(from p1: SIMD2<Double>, to p2: SIMD2<Double>, radii: SIMD2<Double>, turn: Double,
                    large: Bool, sweep: Bool) -> [PathPiece] {
        var rx = radii.x, ry = radii.y
        guard rx > 0, ry > 0, p1 != p2 else { return [.line(p2)] }
        let cosT = cos(turn), sinT = sin(turn)
        func turned(_ v: SIMD2<Double>) -> SIMD2<Double> { SIMD2(cosT * v.x - sinT * v.y, sinT * v.x + cosT * v.y) }
        // The start relative to the middle of the two ends, in the ellipse's own axes.
        let h = (p1 - p2) / 2
        let x1 = cosT * h.x + sinT * h.y, y1 = cosT * h.y - sinT * h.x
        // Radii too small to span the ends grow until they just do.
        let over = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if over > 1 {
            rx *= over.squareRoot()
            ry *= over.squareRoot()
        }
        let across = rx * rx * y1 * y1 + ry * ry * x1 * x1
        let k = (large == sweep ? -1.0 : 1.0) * max(0, (rx * rx * ry * ry - across) / across).squareRoot()
        let cx = k * rx * y1 / ry, cy = -k * ry * x1 / rx
        let centre = turned(SIMD2(cx, cy)) + (p1 + p2) / 2
        let from = atan2((y1 - cy) / ry, (x1 - cx) / rx)
        var span = atan2((-y1 - cy) / ry, (-x1 - cx) / rx) - from
        if sweep, span < 0 { span += 2 * .pi }
        if !sweep, span > 0 { span -= 2 * .pi }
        let parts = max(1, Int((abs(span) / (.pi / 2) - 1e-9).rounded(.up)))
        let step = span / Double(parts)
        let reach = 4.0 / 3 * tan(step / 4)
        func point(_ a: Double) -> SIMD2<Double> { centre + turned(SIMD2(rx * cos(a), ry * sin(a))) }
        func tangent(_ a: Double) -> SIMD2<Double> { turned(SIMD2(-rx * sin(a), ry * cos(a))) }
        return (0..<parts).map { n in
            let a = from + Double(n) * step, b = a + step
            return .curve(point(a) + reach * tangent(a), point(b) - reach * tangent(b), n == parts - 1 ? p2 : point(b))
        }
    }
}

/// Command letters and numbers, in turn, from path data.
private struct PathText {
    private let characters: [Character]
    private var i = 0

    init(_ text: String) { characters = Array(text) }

    var atEnd: Bool {
        mutating get {
            skipSeparators()
            return i >= characters.count
        }
    }

    /// The command letter that comes next, if one does.
    mutating func command() -> Character? {
        skipSeparators()
        guard i < characters.count, characters[i].isLetter else { return nil }
        defer { i += 1 }
        return characters[i]
    }

    /// The number that comes next, if one does.
    mutating func number() -> Double? {
        skipSeparators()
        var j = i
        if j < characters.count, characters[j] == "-" || characters[j] == "+" { j += 1 }
        var digits = false, point = false
        while j < characters.count {
            let c = characters[j]
            if c.isASCII, c.isNumber {
                digits = true
            } else if c == ".", !point {
                point = true
            } else {
                break
            }
            j += 1
        }
        guard digits, let value = Double(String(characters[i..<j])) else { return nil }
        i = j
        return value
    }

    private mutating func skipSeparators() {
        while i < characters.count, characters[i] == " " || characters[i] == "," || characters[i].isNewline {
            i += 1
        }
    }
}

//
//  SceneDrawing.swift
//  BreatheFree
//
//  Colours, clouds, the orb and the box. Kept in step with the Android app's Sky.kt and
//  Scene.kt so both apps look the same.
//

import SwiftUI

// MARK: - Colour

struct RGB {
    var r: Double
    var g: Double
    var b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    func mix(_ other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    func color(_ opacity: Double = 1) -> Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

enum Ink {
    static let deep = RGB(0x0F2A43).color()
    static let soft = RGB(0x3D5A73).color()
    static let accent = RGB(0x0E5A73).color()
    static let accentPressed = RGB(0x0A4559).color()
    static let countdown = RGB(0x0B3A55)
}

/// Colours for one mood of the sky. "Lift" colours are where it brightens to on a full breath.
struct SkyPalette {
    var top: RGB
    var mid: RGB
    var bottom: RGB
    var liftTop: RGB
    var liftMid: RGB
    var liftBottom: RGB
    var cloud: RGB
    var cloudAlpha: Double

    init(top: RGB, mid: RGB, bottom: RGB, lift: (RGB, RGB, RGB)? = nil, cloud: RGB, cloudAlpha: Double) {
        self.top = top
        self.mid = mid
        self.bottom = bottom
        liftTop = lift?.0 ?? top
        liftMid = lift?.1 ?? mid
        liftBottom = lift?.2 ?? bottom
        self.cloud = cloud
        self.cloudAlpha = cloudAlpha
    }

    func mix(_ o: SkyPalette, _ t: Double) -> SkyPalette {
        var p = self
        p.top = top.mix(o.top, t)
        p.mid = mid.mix(o.mid, t)
        p.bottom = bottom.mix(o.bottom, t)
        p.liftTop = liftTop.mix(o.liftTop, t)
        p.liftMid = liftMid.mix(o.liftMid, t)
        p.liftBottom = liftBottom.mix(o.liftBottom, t)
        p.cloud = cloud.mix(o.cloud, t)
        p.cloudAlpha = cloudAlpha + (o.cloudAlpha - cloudAlpha) * t
        return p
    }
}

enum SkyMood {
    case day, dusk, dawn

    var palette: SkyPalette {
        switch self {
        case .day:
            // Home: a clear daytime sky.
            return SkyPalette(top: RGB(0x9FCFF2), mid: RGB(0xCBE6F8), bottom: RGB(0xEEF7FD),
                              cloud: RGB(0xFFFFFF), cloudAlpha: 0.85)
        case .dusk:
            // During a session: dusk, brightening a little as the lungs fill.
            return SkyPalette(top: RGB(0x081A33), mid: RGB(0x12375C), bottom: RGB(0x23607F),
                              lift: (RGB(0x0E2A52), RGB(0x1C4F7E), RGB(0x317C9B)),
                              cloud: RGB(0xAFC3E0), cloudAlpha: 0.30)
        case .dawn:
            // Finished: first light.
            return SkyPalette(top: RGB(0x1D3B66), mid: RGB(0x5F86B5), bottom: RGB(0xF0C9A9),
                              cloud: RGB(0xFFE8DA), cloudAlpha: 0.55)
        }
    }
}

/// Eases the sky from one mood to another, restarting cleanly if retargeted mid-way.
final class PaletteTransition {
    private var from: SkyPalette
    private var to: SkyMood
    private var start: Double = 0
    private var settled = true
    private let seconds = 1.8

    init(_ mood: SkyMood) {
        from = mood.palette
        to = mood
    }

    func retarget(_ mood: SkyMood, at now: Double) {
        guard mood != to else { return }
        from = palette(at: now)
        to = mood
        start = now
        settled = false
    }

    func palette(at now: Double) -> SkyPalette {
        if settled { return to.palette }
        let x = min(max((now - start) / seconds, 0), 1)
        if x >= 1 {
            settled = true
            return to.palette
        }
        return from.mix(to.palette, x * x * (3 - 2 * x))
    }
}

/// Orb colours, from empty lungs (low) to full (high).
struct OrbColors {
    let coreLow: RGB
    let coreHigh: RGB
    let edgeLow: RGB
    let edgeHigh: RGB
    let glow: RGB

    static let night = OrbColors(coreLow: RGB(0x7CC9E6), coreHigh: RGB(0xC6F6FB),
                                 edgeLow: RGB(0x1D6CA0), edgeHigh: RGB(0x39B6D8), glow: RGB(0x86E3F4))
    static let day = OrbColors(coreLow: RGB(0xBDEFF8), coreHigh: RGB(0xE6FBFE),
                               edgeLow: RGB(0x2B95C2), edgeHigh: RGB(0x3FB8D9), glow: RGB(0x7FD6EE))
}

// MARK: - Sky and clouds

/// The small seeded generator the web and Android versions use, so every platform draws the same sky.
struct Mulberry32 {
    private var a: UInt32

    init(seed: UInt32) { a = seed }

    mutating func next() -> Double {
        a = a &+ 0x6D2B_79F5
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}

/// Procedural clouds. Each is a cluster of soft puffs whose offsets and sizes sway on slow,
/// unrelated sine waves, so the clouds gently change shape while they drift, nearer ones
/// faster. Positions are worked out from the time alone, so the sky is the same however
/// irregularly frames arrive.
final class CloudField {
    static let shared = CloudField()

    private struct Puff {
        var dx, dy, r, alpha: Double
        var ax1, wx1, px1, ax2, wx2, px2: Double
        var ay1, wy1, py1: Double
        var ar1, wr1, pr1, ar2, wr2, pr2: Double
    }

    private struct Cloud {
        let id: Int
        let x0: Double
        let depth: Double
        let speed: Double
        let opacity: Double
        let bobAmp: Double
        let bobFreq: Double
        let bobPhase: Double
        let puffs: [Puff]
    }

    private static let margin = 0.22 // clouds enter and leave fully formed
    private let clouds: [Cloud]

    /// A soft round puff, drawn once and stamped many times to build the clouds.
    static let puff: CGImage = {
        let size = 128
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [1.0, 0.9, 0.55, 0.2, 0.0].map { CGColor(srgbRed: 1, green: 1, blue: 1, alpha: $0) } as CFArray
        let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.3, 0.55, 0.78, 1])!
        let c = CGPoint(x: Double(size) / 2, y: Double(size) / 2)
        ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: Double(size) / 2, options: [])
        return ctx.makeImage()!
    }()

    init(seed: UInt32 = 20_240_607, count: Int = 9) {
        var rand = Mulberry32(seed: seed)
        var made: [Cloud] = []
        for i in 0..<count {
            // Spread the starting points so the sky never starts empty or bunched up.
            let x0 = -Self.margin + ((Double(i) + rand.next() * 0.8) / Double(count)) * (1 + 2 * Self.margin)
            made.append(Self.makeCloud(id: i, rand: &rand, x0: x0))
        }
        clouds = made.sorted { $0.depth < $1.depth } // far clouds first
    }

    func draw(in context: inout GraphicsContext, size: CGSize, time t: Double, palette: SkyPalette, sprite: GraphicsContext.ResolvedImage) {
        let w = Double(size.width)
        let h = Double(size.height)
        let sizeBase = min(max(w, 480), 1600)
        let span = 1 + 2 * Self.margin
        context.drawLayer { layer in
            layer.addFilter(.colorMultiply(palette.cloud.color()))
            for c in clouds {
                let travelled = c.x0 + Self.margin + c.speed * t
                let laps = (travelled / span).rounded(.down)
                let xFrac = travelled - laps * span - Self.margin
                // Each time a cloud comes round again it enters at a new height.
                let yFrac = 0.06 + 0.74 * Self.hash01(c.id, Int(laps))
                let cloudSize = sizeBase * (0.09 + c.depth * 0.13)
                let cx = xFrac * w
                let cy = yFrac * h + sin(t * c.bobFreq * 2 * .pi + c.bobPhase) * c.bobAmp * cloudSize
                for p in c.puffs {
                    let px = cx + (p.dx + p.ax1 * sin(t * p.wx1 + p.px1) + p.ax2 * sin(t * p.wx2 + p.px2)) * cloudSize
                    let py = cy + (p.dy + p.ay1 * sin(t * p.wy1 + p.py1)) * cloudSize
                    let pr = p.r * (1 + p.ar1 * sin(t * p.wr1 + p.pr1) + p.ar2 * sin(t * p.wr2 + p.pr2)) * cloudSize
                    let alpha = min(max(c.opacity * p.alpha * palette.cloudAlpha, 0), 1)
                    if alpha <= 0.003 { continue }
                    layer.opacity = alpha
                    layer.draw(sprite, in: CGRect(x: px - pr, y: py - pr, width: 2 * pr, height: 2 * pr))
                }
            }
        }
    }

    private static func makePuff(_ rand: inout Mulberry32, spreadX: Double) -> Puff {
        Puff(
            dx: (rand.next() * 2 - 1) * spreadX,
            dy: (rand.next() * 2 - 1) * 0.16,
            r: 0.22 + rand.next() * 0.2,
            alpha: 0.55 + rand.next() * 0.45,
            ax1: 0.015 + rand.next() * 0.03, wx1: 0.15 + rand.next() * 0.25, px1: rand.next() * 2 * .pi,
            ax2: 0.008 + rand.next() * 0.015, wx2: 0.4 + rand.next() * 0.35, px2: rand.next() * 2 * .pi,
            ay1: 0.012 + rand.next() * 0.025, wy1: 0.12 + rand.next() * 0.22, py1: rand.next() * 2 * .pi,
            ar1: 0.04 + rand.next() * 0.05, wr1: 0.1 + rand.next() * 0.18, pr1: rand.next() * 2 * .pi,
            ar2: 0.02 + rand.next() * 0.03, wr2: 0.3 + rand.next() * 0.3, pr2: rand.next() * 2 * .pi
        )
    }

    private static func makeCloud(id: Int, rand: inout Mulberry32, x0: Double) -> Cloud {
        let depth = rand.next()
        let puffCount = 6 + Int(rand.next() * 4)
        var puffs: [Puff] = []
        for _ in 0..<puffCount { puffs.append(makePuff(&rand, spreadX: 0.55)) }
        // A flatter, fuller puff along the bottom gives each cloud a level base.
        var base = makePuff(&rand, spreadX: 0.35)
        base.dy = 0.16
        base.r = 0.34
        base.alpha = 0.8
        puffs.append(base)
        return Cloud(
            id: id, x0: x0, depth: depth,
            // Nearer clouds drift faster: roughly 45 to 110 seconds to cross the screen.
            speed: (0.009 + depth * 0.013) * (rand.next() < 0.5 ? 1 : 1.15),
            opacity: 0.3 + depth * 0.45,
            bobAmp: 0.02 + rand.next() * 0.03,
            bobFreq: 0.03 + rand.next() * 0.05,
            bobPhase: rand.next() * 2 * .pi,
            puffs: puffs
        )
    }

    private static func hash01(_ a: Int, _ b: Int) -> Double {
        var x = (UInt32(truncatingIfNeeded: a) &* 0x27D4_EB2D) ^ (UInt32(truncatingIfNeeded: b) &* 0x1656_67B1) ^ 0x5BD1_E995
        x ^= x >> 15
        x = x &* 0x2C1B_3C6D
        x ^= x >> 12
        x = x &* 0x297A_2D39
        x ^= x >> 15
        return Double(x) / 4_294_967_296.0
    }
}

// MARK: - Session scene

/// Where the box and orb sit, in points. The text layout uses the same numbers.
struct SceneGeometry {
    let cx: Double
    let cy: Double
    let half: Double

    var corner: Double { half * 0.2 }
    var orbMin: Double { half * 0.36 }
    var orbMax: Double { half * 0.82 }

    func orbRadius(_ level: Double) -> Double { orbMin + (orbMax - orbMin) * level }

    static func of(_ size: CGSize) -> SceneGeometry {
        let w = Double(size.width)
        let h = Double(size.height)
        let portrait = h >= w
        let half = portrait ? min(w * 0.34, h * 0.2) : min(w * 0.2, h * 0.27)
        return SceneGeometry(cx: w / 2, cy: h * (portrait ? 0.43 : 0.45), half: half)
    }
}

enum SceneDrawing {
    private static let ripplesLast = 2.4

    static func sky(_ context: inout GraphicsContext, size: CGSize, palette p: SkyPalette, level: Double) {
        let lift = level * 0.65
        let gradient = Gradient(colors: [p.top.mix(p.liftTop, lift).color(),
                                         p.mid.mix(p.liftMid, lift).color(),
                                         p.bottom.mix(p.liftBottom, lift).color()])
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
    }

    static func orb(_ context: inout GraphicsContext, center: CGPoint, radius: Double, level: Double,
                    colors: OrbColors, alpha: Double = 1) {
        guard alpha > 0, radius > 0 else { return }
        // Halo: strongest at the rim, gone by about twice the radius; fuller breath, wider glow.
        let haloRadius = radius * (1.9 + 0.35 * level)
        let haloAlpha = (0.26 + 0.22 * level) * alpha
        let rim = (radius / haloRadius) * 0.92
        context.fill(
            Path(ellipseIn: circle(center, haloRadius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: colors.glow.color(haloAlpha), location: 0),
                    .init(color: colors.glow.color(haloAlpha), location: rim),
                    .init(color: colors.glow.color(0), location: 1),
                ]),
                center: center, startRadius: 0, endRadius: haloRadius
            )
        )
        // Body: lit from the upper left.
        let core = colors.coreLow.mix(colors.coreHigh, level)
        let edge = colors.edgeLow.mix(colors.edgeHigh, level)
        context.fill(
            Path(ellipseIn: circle(center, radius)),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0.95 * alpha), location: 0),
                    .init(color: core.color(alpha), location: 0.35),
                    .init(color: edge.color(alpha), location: 1),
                ]),
                center: CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.32),
                startRadius: 0, endRadius: radius * 1.45
            )
        )
        context.stroke(Path(ellipseIn: circle(center, radius - 0.75)),
                       with: .color(Color.white.opacity(0.22 * alpha)), lineWidth: 1.5)
    }

    /// The box, the trail of the current cycle, the ripples, the orb and the travelling dot
    /// for one instant of a session. `t` is session time in seconds.
    static func session(_ context: inout GraphicsContext, geometry g: SceneGeometry, frame: BreathFrame, time t: Double) {
        let settling = frame.stage == .settle
        let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)

        // The outline draws itself during the first seconds of the settle.
        let outline = settling ? BreathCurve.rise(t / 2.5) : 1
        context.stroke(boxPath(g, to: 4 * outline), with: .color(Color.white.opacity(0.16)), style: line)

        let side = frame.boxSide
        let along = frame.boxFraction
        if frame.stage == .breathing {
            context.stroke(boxPath(g, to: Double(side) + along), with: .color(Color.white.opacity(0.5)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            // Ripples: a ring leaves the orb at each change of phase.
            if let phase = frame.phase {
                ripple(&context, g, phase: phase, age: frame.phaseElapsed)
                if frame.phaseIndex > 0, let previous = Phase(rawValue: (frame.phaseIndex - 1) % 4) {
                    ripple(&context, g, phase: previous, age: frame.phaseElapsed + SessionPlan.phaseSeconds)
                }
            }
        }

        let orbAlpha = settling ? min(max(t / 1.2, 0), 1) : 1
        orb(&context, center: CGPoint(x: g.cx, y: g.cy), radius: g.orbRadius(frame.level), level: frame.level,
            colors: .night, alpha: orbAlpha)

        // The dot fades in at the start corner as the settle ends.
        let dotAlpha: Double
        switch frame.stage {
        case .settle: dotAlpha = min(max((t - (SessionPlan.settleSeconds - 1.5)) / 1.5, 0), 1)
        case .breathing: dotAlpha = 1
        case .complete: dotAlpha = 0
        }
        if dotAlpha > 0 {
            let p = BoxGeometry.point(side: side, f: along, cx: g.cx, cy: g.cy, h: g.half, r: g.corner)
            let centre = CGPoint(x: p.x, y: p.y)
            let glow = RGB(0xBDF3FA)
            context.fill(Path(ellipseIn: circle(centre, 16)),
                         with: .radialGradient(Gradient(colors: [glow.color(0.7 * dotAlpha), glow.color(0)]),
                                               center: centre, startRadius: 0, endRadius: 16))
            context.fill(Path(ellipseIn: circle(centre, 5)), with: .color(Color.white.opacity(dotAlpha)))
        }
    }

    private static func ripple(_ context: inout GraphicsContext, _ g: SceneGeometry, phase: Phase, age: Double) {
        guard age < ripplesLast else { return }
        let startRadius = (phase == .inhale || phase == .holdEmpty) ? g.orbMin : g.orbMax
        let strength = (phase == .inhale || phase == .exhale) ? 0.32 : 0.2
        let fade = 1 - age / ripplesLast
        context.stroke(Path(ellipseIn: circle(CGPoint(x: g.cx, y: g.cy), startRadius + age * g.half * 0.3)),
                       with: .color(Color.white.opacity(strength * fade * fade)), lineWidth: 1.5)
    }

    /// The outline from its start (the middle of the bottom-left corner) to quarter-position
    /// `to` (0...4 = once round), traced through the same geometry the dot uses.
    private static func boxPath(_ g: SceneGeometry, to: Double) -> Path {
        var path = Path()
        guard to > 0 else { return path }
        let steps = max(1, Int(to * 96))
        for i in 0...steps {
            let q = to * Double(i) / Double(steps)
            let s = min(3, Int(q))
            let p = BoxGeometry.point(side: s, f: q - Double(s), cx: g.cx, cy: g.cy, h: g.half, r: g.corner)
            if i == 0 { path.move(to: CGPoint(x: p.x, y: p.y)) } else { path.addLine(to: CGPoint(x: p.x, y: p.y)) }
        }
        return path
    }

    static func circle(_ c: CGPoint, _ r: Double) -> CGRect {
        CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }
}

//
//  LiquidPicker.swift
//  BreatheFree
//
//  Session length as liquid. When the picker opens, the other counts bud out of the chosen one
//  and pull free as drops; when one is picked, they all flow back into it. Drops run into one
//  another wherever they come close, as far as each drop's reach, and the reach eases to nothing
//  as a drop settles, so at rest they are plain circles. Every value is a function of time, so
//  the picker can draw any moment of the motion. The settings fan (SettingsFan.swift) is the
//  same liquid, its drops going out on a slant (LiquidFan, FanMotion). Kept in step with the
//  Android app's LiquidPicker.kt and the browser version's liquid.ts.
//

import Foundation

/// One drop of liquid. A row's drops sit on its line, which is the default.
struct LiquidDrop: Equatable {
    /// Its centre along the row.
    var x: Double
    var radius: Double
    /// How far it is drawn out along the way it moves; 1 is round.
    var stretch = 1.0
    /// How far it runs into the drops before it.
    var reach = 0.0
    /// Its centre below the row's line (0 on it).
    var y = 0.0
    /// The way it moves, in radians clockwise from along the row (0, the default).
    var angle = 0.0

    /// Distance from its edge, negative inside: exact when round, close when stretched.
    func distance(_ px: Double, _ py: Double) -> Double { MeasuredDrop(self).distance(px, py) }
}

/// A drop ready to measure from: its centre, its half-lengths and the way it is drawn out.
private struct MeasuredDrop {
    let x, y, a, b, c, s, reach: Double

    init(_ d: LiquidDrop) {
        x = d.x
        y = d.y
        a = d.radius * d.stretch
        b = d.radius / d.stretch
        c = cos(d.angle)
        s = sin(d.angle)
        reach = d.reach
    }

    func distance(_ px: Double, _ py: Double) -> Double {
        let ox = px - x, oy = py - y
        // Along the way it moves, and across it.
        let dx = (ox * c + oy * s) / a, dy = (oy * c - ox * s) / b
        return ((dx * dx + dy * dy).squareRoot() - 1) * b
    }
}

/// The outline of a row of drops that run into one another, so the row can be drawn as one shape.
enum LiquidOutline {
    /// The outline round `drops`, `inset` inside their edge, as closed loops of points. Each drop
    /// runs into those before it wherever they come within its reach (a smooth minimum of their
    /// distances), so the drop the others leave and return to goes first. Traced with marching
    /// squares over squares of side `cell`.
    static func loops(_ drops: [LiquidDrop], inset: Double = 0, cell: Double = 1.5) -> [[SIMD2<Double>]] {
        let live = drops.filter { $0.radius > 0.05 }
        guard !live.isEmpty, cell > 0 else { return [] }
        // The squares cover each drop as far as its reach along the way it moves, and a quarter
        // of that across it.
        var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
        for d in live {
            let along = d.radius * d.stretch + d.reach, across = d.radius + d.reach / 4
            let c = abs(cos(d.angle)), s = abs(sin(d.angle))
            let halfX = c * along + s * across, halfY = s * along + c * across
            x0 = min(x0, d.x - halfX)
            x1 = max(x1, d.x + halfX)
            y0 = min(y0, d.y - halfY)
            y1 = max(y1, d.y + halfY)
        }
        x0 -= 2 * cell
        x1 += 2 * cell
        y0 -= 2 * cell
        y1 += 2 * cell
        let nx = Int(((x1 - x0) / cell).rounded(.up)) + 1
        let ny = Int(((y1 - y0) / cell).rounded(.up)) + 1
        let measured = live.map(MeasuredDrop.init)
        var v = [Double](repeating: 0, count: nx * ny)
        for j in 0..<ny {
            let y = y0 + Double(j) * cell
            for i in 0..<nx {
                v[j * nx + i] = field(measured, x0 + Double(i) * cell, y) + inset
            }
        }

        // Marching squares, inside where v < 0. A crossing is named by its grid edge: twice the
        // index of the point the edge starts from, plus one if it goes down rather than right.
        // Each crossing is linked to the two crossings it joins.
        var links = [Int](repeating: -1, count: 4 * nx * ny)
        func join(_ a: Int, _ b: Int) {
            links[2 * a + (links[2 * a] < 0 ? 0 : 1)] = b
            links[2 * b + (links[2 * b] < 0 ? 0 : 1)] = a
        }
        for j in 0..<(ny - 1) {
            for i in 0..<(nx - 1) {
                let k = j * nx + i
                let tl = v[k], tr = v[k + 1], br = v[k + nx + 1], bl = v[k + nx]
                let corners = (tl < 0 ? 1 : 0) | (tr < 0 ? 2 : 0) | (br < 0 ? 4 : 0) | (bl < 0 ? 8 : 0)
                let top = 2 * k, bottom = 2 * (k + nx), left = 2 * k + 1, right = 2 * (k + 1) + 1
                switch corners {
                case 1, 14: join(left, top)
                case 2, 13: join(top, right)
                case 3, 12: join(left, right)
                case 4, 11: join(right, bottom)
                case 6, 9: join(top, bottom)
                case 7, 8: join(left, bottom)
                case 5, 10:
                    // Opposite corners inside: joined through the middle if the middle is inside.
                    if (corners == 5) == ((tl + tr + br + bl) / 4 < 0) {
                        join(top, right)
                        join(bottom, left)
                    } else {
                        join(left, top)
                        join(right, bottom)
                    }
                default:
                    break
                }
            }
        }

        func point(_ e: Int) -> SIMD2<Double> {
            let k = e / 2, i = k % nx, j = k / nx
            let a = v[k], b = v[e % 2 == 0 ? k + 1 : k + nx]
            let t = a / (a - b)
            return e % 2 == 0
                ? SIMD2(x0 + (Double(i) + t) * cell, y0 + Double(j) * cell)
                : SIMD2(x0 + Double(i) * cell, y0 + (Double(j) + t) * cell)
        }

        var loops: [[SIMD2<Double>]] = []
        var seen = [Bool](repeating: false, count: 2 * nx * ny)
        for start in 0..<(2 * nx * ny) where links[2 * start] >= 0 && !seen[start] {
            var loop: [SIMD2<Double>] = []
            var previous = -1, current = start
            while !seen[current] {
                seen[current] = true
                loop.append(point(current))
                let a = links[2 * current], b = links[2 * current + 1]
                let next = a != previous ? a : b
                guard next >= 0 else { break }
                previous = current
                current = next
            }
            if loop.count > 2 { loops.append(loop) }
        }
        return loops
    }

    /// The liquid's distance field: each drop run into those before it.
    static func field(_ drops: [LiquidDrop], _ x: Double, _ y: Double) -> Double {
        field(drops.map(MeasuredDrop.init), x, y)
    }

    private static func field(_ drops: [MeasuredDrop], _ x: Double, _ y: Double) -> Double {
        var u = drops[0].distance(x, y)
        for d in drops.dropFirst() {
            u = smoothMin(u, d.distance(x, y), d.reach)
        }
        return u
    }

    /// The smaller of `a` and `b`, rounded into a fillet where they are within `k` of each other.
    static func smoothMin(_ a: Double, _ b: Double, _ k: Double) -> Double {
        guard k > 1e-4 else { return min(a, b) }
        let h = max(k - abs(a - b), 0) / k
        return min(a, b) - h * h * h * k / 6
    }
}

/// One count's drop at a moment of the picker's motion.
struct PickerDrop: Equatable {
    var x: Double
    var radius: Double
    var stretch: Double
    var reach: Double
    /// How much of the chosen colour it wears: 1 for the chosen count.
    var accent: Double
    /// How clearly its count shows.
    var label: Double

    var liquid: LiquidDrop { LiquidDrop(x: x, radius: radius, stretch: stretch, reach: reach) }
}

/// How the session-length drops move. Opening, the others bud out of the chosen drop and spring
/// to their places, those further out a moment later; closing, they all flow back into the
/// chosen one, which takes on the chosen colour if it was just picked. A drop's spread is 0 at
/// home inside the chosen drop and 1 in its place.
struct PickerMotion: Equatable {
    static let openResponse = 0.42
    static let openDamping = 0.68
    static let stagger = 0.028
    static let closeResponse = 0.34
    /// How long a picked drop takes to wear the chosen colour.
    static let recolour = 0.1
    /// From a change until every spring has come to rest.
    static let duration = 1.2

    /// When the picker last opened or closed, on the media clock.
    var changedAt = -Double.infinity
    var opening: Bool
    /// Each drop's spread at that moment.
    var from: [Double]
    /// The count the drops leave or flow into, and the one chosen before (they differ after a pick).
    var chosen: Int
    var previous: Int

    /// At rest, open or closed.
    init(count: Int, open: Bool, chosen: Int) {
        opening = open
        from = Array(repeating: open ? 1 : 0, count: count)
        self.chosen = chosen
        previous = chosen
    }

    /// A move that starts at `time` from wherever the drops are then.
    func changed(open: Bool, chosen: Int, at time: Double) -> PickerMotion {
        var next = self
        next.from = from.indices.map { spread($0, at: time).value }
        next.changedAt = time
        next.opening = open
        next.previous = self.chosen
        next.chosen = chosen
        return next
    }

    func isSettled(at time: Double) -> Bool { time - changedAt > Self.duration }

    /// Drop `i`'s spread at `time`, and how fast it is changing.
    func spread(_ i: Int, at time: Double) -> (value: Double, velocity: Double) {
        let t = time - changedAt
        if opening {
            let (p, rate) = Self.spring(t - Self.stagger * Double(abs(i - chosen)),
                                        response: Self.openResponse, damping: Self.openDamping)
            return (from[i] + (1 - from[i]) * p, (1 - from[i]) * rate)
        }
        let (p, rate) = Self.spring(t, response: Self.closeResponse, damping: 1)
        return (from[i] * (1 - p), -from[i] * rate)
    }

    /// The order the drops run into one another: the chosen one first, then outwards.
    var order: [Int] {
        from.indices.sorted { (abs($0 - chosen), $0) < (abs($1 - chosen), $1) }
    }

    /// Every count's drop at `time`, for drops `size` across set `step` apart.
    func drops(at time: Double, size: Double, step: Double) -> [PickerDrop] {
        let count = from.count
        let r = size / 2
        let spreads = (0..<count).map { spread($0, at: time) }
        let others = (0..<count).filter { $0 != chosen }
        let out = others.isEmpty ? 0 : others.map { clamp(spreads[$0].value) }.reduce(0, +) / Double(others.count)
        let recolour = opening ? 1 : smoothstep(0, Self.recolour, time - changedAt)
        var drops = (0..<count).map { i -> PickerDrop in
            let (s, rate) = spreads[i]
            let slot = (Double(i) - Double(count - 1) / 2) * step
            // Drops on the move are drawn out along the way they go.
            let stretch = 1 + 0.14 * min(1, abs(rate * slot) / step / 13)
            if i == chosen {
                // The chosen drop gives a little as the others leave it, and swells as they return.
                let swell = (opening ? -0.04 : 0.06) * sin(.pi * out)
                return PickerDrop(x: slot * s, radius: r * (1 + swell), stretch: stretch, reach: 0,
                                  accent: i == previous ? 1 : recolour, label: 1)
            }
            return PickerDrop(x: slot * s, radius: r * Self.grow(s), stretch: stretch,
                              reach: 0.48 * size * pow(1 - clamp(s), 1.4),
                              accent: i == previous ? 1 - recolour : 0, label: 0)
        }
        // A count shows once its drop is clear of the others.
        for i in others {
            let d = drops[i]
            let gap = drops.indices.filter { $0 != i && drops[$0].radius > 0.05 }.map {
                abs(d.x - drops[$0].x) - d.radius * d.stretch - drops[$0].radius * drops[$0].stretch
            }.min() ?? .infinity
            drops[i].label = smoothstep(0.72, 0.97, spreads[i].value) * smoothstep(0, 0.09 * size, gap)
        }
        return drops
    }

    /// A drop's size for its spread: nothing at home, its full size in place, and a little more
    /// while the spring carries it past.
    static func grow(_ s: Double) -> Double {
        s > 1 ? 1 + 0.4 * (s - 1) : max(0, s * (2 - s))
    }

    /// SwiftUI's spring(response:dampingFraction:) from rest at 0 towards 1, `t` seconds in, and
    /// its rate.
    static func spring(_ t: Double, response: Double, damping: Double) -> (Double, Double) {
        guard t > 0 else { return (0, 0) }
        guard t < 10 else { return (1, 0) }
        let w = 2 * Double.pi / response
        if damping < 1 {
            let wd = w * (1 - damping * damping).squareRoot()
            let e = exp(-damping * w * t)
            return (1 - e * (cos(wd * t) + damping * w / wd * sin(wd * t)), e * w * w / wd * sin(wd * t))
        }
        let e = exp(-w * t)
        return (1 - e * (1 + w * t), w * w * t * e)
    }
}

/// A setting's drop in the fan at a moment of its motion.
struct FanDrop: Equatable {
    var x: Double
    var y: Double
    var radius: Double
    var stretch: Double
    /// The way it moves, in radians clockwise from along the row.
    var angle: Double
    var reach: Double
    /// How much of the lit colour it wears: how far its setting is on, once it arrives.
    var accent: Double
    /// How clearly its icon shows.
    var label: Double

    var liquid: LiquidDrop { LiquidDrop(x: x, radius: radius, stretch: stretch, reach: reach, y: y, angle: angle) }
}

/// The fan at one moment: the round button's own drop, and the settings' drops in order.
struct FanShape: Equatable {
    var home: LiquidDrop
    var drops: [FanDrop]
}

/// The settings fan, opening as a hand fan does. Folded, it lies flat to the button's left: the
/// drops come out of the round button (`button` across) together, as one drop, to `distance`
/// from its centre, and swing round it from there, down toward below it, each 45 degrees round
/// from the one before, the fan centred on the quarter circle (two at 22.5 and 67.5 degrees,
/// three at 0, 45 and 90), the later ones further, pulling free of the ones before them as they
/// go. A drop's out is 0 at home inside the button and 1 at its distance; its sweep is 0 folded
/// flat and 1 in its place. The rates say how fast they change (per second), and `lit` how far
/// each drop's setting is on. Kept in step with the browser version's fanDrops and the Android
/// app's LiquidFan.
enum LiquidFan {
    static func drops(outs: [Double], outRates: [Double], sweeps: [Double], sweepRates: [Double], lit: [Double],
                      opening: Bool, size: Double, button: Double, distance: Double) -> FanShape {
        let count = outs.count
        let r = size / 2
        func reachAt(_ s: Double) -> Double { 0.48 * size * pow(1 - clamp(s), 1.4) }
        let out = count > 0 ? outs.map(clamp).reduce(0, +) / Double(count) : 0
        // The button gives a little as the drops leave it, and swells as they return.
        let swell = (opening ? -0.04 : 0.06) * sin(.pi * out)
        let home = LiquidDrop(x: 0, radius: button / 2 * (1 + swell))
        var drops = (0..<count).map { i -> FanDrop in
            let s = outs[i]
            // How far round from the button's left its place is, toward below: 45 degrees on
            // from the one before, the fan centred on the quarter circle.
            let swing = Double.pi / 4 * (1 + Double(i) - Double(count - 1) / 2)
            let angle = Double.pi - swing * sweeps[i]
            let along = distance * s
            // Its velocity: out from the button, and round it.
            let c = cos(angle), sn = sin(angle)
            let outward = distance * outRates[i]
            let turning = along * swing * sweepRates[i]
            let vx = outward * c + turning * sn, vy = outward * sn - turning * c
            // Drawn out along the way it goes, as much as a row's drop at the same speed.
            let stretch = 1 + 0.14 * min(1, (vx * vx + vy * vy).squareRoot() / (size + 8) / 13)
            // Coming out it runs into the button; swinging round, into the drops it leaves.
            let sweepReach = i == 0 ? 0 : reachAt(sweeps[i])
            let arrived = min(clamp(s), clamp(sweeps[i]))
            return FanDrop(x: c * along, y: sn * along, radius: r * PickerMotion.grow(s), stretch: stretch,
                           angle: atan2(vy, vx), reach: max(reachAt(s), sweepReach),
                           accent: lit[i] * smoothstep(0.45, 0.95, arrived), label: smoothstep(0.72, 0.97, arrived))
        }
        // An icon shows once its drop is in its place and clear of the button and the others.
        let all = [home] + drops.map(\.liquid)
        for i in drops.indices {
            let d = drops[i]
            var gap = Double.infinity
            for (j, o) in all.enumerated() where j != i + 1 && o.radius > 0.05 {
                gap = min(gap, hypot(d.x - o.x, d.y - o.y) - d.radius * d.stretch - o.radius * o.stretch)
            }
            drops[i].label *= smoothstep(0, 0.09 * size, gap)
        }
        return FanShape(home: home, drops: drops)
    }
}

/// How the settings fan moves, as a function of time like the picker's. Opening, the drops come
/// out of the button together and a moment later swing round to their places; folding, they
/// swing back into one and then go home, at once if they had not yet swung open. For those who
/// ask for less motion they stand in their places and fade in and out instead. A drop's colour
/// eases on and off as its setting changes.
struct FanMotion: Equatable {
    /// The browser version's springs, as SwiftUI-style responses: out from the button and round
    /// it, each with a little bounce, as a fan's blades.
    static let outResponse = 2 * Double.pi / 260.0.squareRoot()
    static let outDamping = 0.62
    static let sweepResponse = 2 * Double.pi / 200.0.squareRoot()
    static let sweepDamping = 0.55
    /// Opening, the drops start to swing round this long after they start to come out...
    static let sweepAfter = 0.05
    /// ...and folding, they go home this long after they start to swing back.
    static let homeAfter = 0.11
    /// How long the drops take to fade in or out, for less motion.
    static let fade = 0.16
    /// From a change until every spring has come to rest.
    static let duration = 1.2

    /// When the fan last opened or folded, on the media clock.
    var changedAt = -Double.infinity
    var opening: Bool
    /// Whether it moves with less motion, fading in and out in place.
    var reduced = false
    /// Each drop's out and sweep at that moment, and how much of the drops showed.
    var fromOut: [Double]
    var fromSweep: [Double]
    var fromShown = 1.0
    /// Folded before they had swung open, the drops go home at once.
    var together = false
    /// Each drop's setting, on or off; how lit each was when one last changed, and when.
    var on: [Bool]
    var fromLit: [Double]
    var litChangedAt = -Double.infinity

    /// At rest, open or folded, its drops lit as `on` says.
    init(open: Bool, lit on: [Bool]) {
        opening = open
        fromOut = on.map { _ in open ? 1 : 0 }
        fromSweep = fromOut
        self.on = on
        fromLit = on.map { $0 ? 1 : 0 }
    }

    /// A move that starts at `time` from wherever the drops are then.
    func changed(open: Bool, reduced: Bool, at time: Double) -> FanMotion {
        var next = self
        next.fromOut = fromOut.indices.map { out($0, at: time).value }
        next.fromSweep = fromSweep.indices.map { sweep($0, at: time).value }
        next.together = next.fromSweep.allSatisfy { $0 < 0.05 }
        // A fade starts from as much as shows now: nothing while the drops are home.
        let home = next.fromOut.allSatisfy({ $0 < 0.05 })
        next.fromShown = self.reduced ? shown(at: time) : home ? 0 : 1
        next.reduced = reduced
        next.changedAt = time
        next.opening = open
        return next
    }

    /// The same move, with the drops' settings turned on or off at `time`.
    func relit(_ on: [Bool], at time: Double) -> FanMotion {
        var next = self
        next.fromLit = fromLit.indices.map { lit($0, at: time) }
        next.on = on
        next.litChangedAt = time
        return next
    }

    func isSettled(at time: Double) -> Bool { time - changedAt > Self.duration }

    /// Drop `i`'s out at `time`, and how fast it is changing.
    func out(_ i: Int, at time: Double) -> (value: Double, velocity: Double) {
        let t = time - changedAt
        // With less motion they stand in their places while they show, and are home once gone.
        if reduced { return (opening || t < Self.fade ? 1 : 0, 0) }
        let from = fromOut[i]
        if opening {
            let (p, rate) = PickerMotion.spring(t, response: Self.outResponse, damping: Self.outDamping)
            return (from + (1 - from) * p, (1 - from) * rate)
        }
        let (p, rate) = PickerMotion.spring(t - (together ? 0 : Self.homeAfter),
                                            response: PickerMotion.closeResponse, damping: 1)
        return (from * (1 - p), -from * rate)
    }

    /// Drop `i`'s sweep at `time`, and how fast it is changing.
    func sweep(_ i: Int, at time: Double) -> (value: Double, velocity: Double) {
        let t = time - changedAt
        if reduced { return (opening || t < Self.fade ? 1 : 0, 0) }
        let from = fromSweep[i]
        if opening {
            let (p, rate) = PickerMotion.spring(t - Self.sweepAfter, response: Self.sweepResponse,
                                                damping: Self.sweepDamping)
            return (from + (1 - from) * p, (1 - from) * rate)
        }
        let (p, rate) = PickerMotion.spring(t, response: PickerMotion.closeResponse, damping: 1)
        return (from * (1 - p), -from * rate)
    }

    /// How much of the drops shows at `time`: all of them, but while fading for less motion.
    func shown(at time: Double) -> Double {
        guard reduced else { return 1 }
        return fromShown + ((opening ? 1 : 0) - fromShown) * clamp((time - changedAt) / Self.fade)
    }

    /// How lit drop `i` is at `time`, its colour easing on or off since its setting changed.
    func lit(_ i: Int, at time: Double) -> Double {
        fromLit[i] + ((on[i] ? 1 : 0) - fromLit[i]) * smoothstep(0, PickerMotion.recolour, time - litChangedAt)
    }

    /// The fan at `time`, for drops `size` across, `distance` from the centre of a round button
    /// `button` across.
    func shape(at time: Double, size: Double, button: Double, distance: Double) -> FanShape {
        let outs = fromOut.indices.map { out($0, at: time) }
        let sweeps = fromSweep.indices.map { sweep($0, at: time) }
        return LiquidFan.drops(outs: outs.map { $0.value }, outRates: outs.map { $0.velocity },
                               sweeps: sweeps.map { $0.value }, sweepRates: sweeps.map { $0.velocity },
                               lit: on.indices.map { lit($0, at: time) }, opening: opening,
                               size: size, button: button, distance: distance)
    }
}

private func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

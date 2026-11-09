//
//  Gestures.swift
//  BreatheFree
//
//  The motion behind four small gestures, worked out from the media clock like everything else
//  on screen, so the views only feed in where the pointer is and when: the orb on the home and
//  done screens can be pulled about (OrbPoke), the session length can be slid along once it is
//  open (BeadSlide), the volume slider gives past its ends (Give), and the ✕ ends a session when
//  held (HoldFill). Kept in step with the Android app's PokableOrb.kt, Controls.kt and
//  BreatheApp.kt, on the same numbers, in points where Android has dp.
//

import Foundation

/// A spring as Android's `spring(dampingRatio, stiffness)`: a mass of 1 on a spring of
/// `stiffness`, damped by `damping` (1 comes to rest as fast as it can without overshooting;
/// less overshoots and wobbles).
struct DampedSpring: Equatable {
    let damping: Double
    let stiffness: Double

    /// Where something let go `x0` from home, moving at `v0`, is `t` seconds later, and its speed.
    func at(_ t: Double, from x0: Double, speed v0: Double) -> (value: Double, velocity: Double) {
        guard t > 0 else { return (x0, v0) }
        let w = stiffness.squareRoot()
        if damping < 1 {
            let wd = w * (1 - damping * damping).squareRoot()
            let a = x0, b = (v0 + damping * w * x0) / wd
            let e = exp(-damping * w * t), c = cos(wd * t), s = sin(wd * t)
            let x = e * (a * c + b * s)
            let v = e * ((b * wd - damping * w * a) * c - (a * wd + damping * w * b) * s)
            return (x, v)
        }
        if damping == 1 {
            let b = v0 + w * x0
            let e = exp(-w * t)
            return (e * (x0 + b * t), e * (v0 - w * b * t))
        }
        let root = (damping * damping - 1).squareRoot()
        let r1 = -w * (damping - root), r2 = -w * (damping + root)
        let c2 = (v0 - r1 * x0) / (r2 - r1), c1 = x0 - c2
        let e1 = exp(r1 * t), e2 = exp(r2 * t)
        return (c1 * e1 + c2 * e2, c1 * r1 * e1 + c2 * r2 * e2)
    }

    /// How long until something let go `x0` from home at `v0` stays within `threshold` of it, as
    /// Android's animations end once within their visibility threshold.
    func settles(from x0: Double, speed v0: Double, within threshold: Double) -> Double {
        let step = 1.0 / 240, end = 5.0
        var last = 0.0
        var t = 0.0
        while t <= end {
            if abs(at(t, from: x0, speed: v0).value) >= threshold { last = t }
            t += step
        }
        return last + step
    }
}

/// How far something held at an edge goes when pulled `overshoot` past it: a little over half as
/// far at first, then less and less, never as far as `limit`. Apple's rubber band, as a scroll
/// view's at its end.
func rubberBand(_ overshoot: Double, limit: Double, constant: Double = 0.55) -> Double {
    overshoot * limit * constant / (limit + constant * abs(overshoot))
}

/// The pull that `rubberBand` takes as far as `band`: the other way round.
func unRubberBand(_ band: Double, limit: Double, constant: Double = 0.55) -> Double {
    let b = min(max(band, -0.999 * limit), 0.999 * limit)
    return b * limit / (constant * (limit - abs(b)))
}

/// The rubber band along the way a point is pulled, for a pull in two directions.
func rubberBand(_ pull: SIMD2<Double>, limit: Double) -> SIMD2<Double> {
    let d = norm(pull)
    return d == 0 ? pull : pull * (rubberBand(d, limit: limit) / d)
}

func unRubberBand(_ band: SIMD2<Double>, limit: Double) -> SIMD2<Double> {
    let d = norm(band)
    return d == 0 ? band : band * (unRubberBand(d, limit: limit) / d)
}

func norm(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

/// How fast the pointer is going, from where it has been lately: a curve fitted to the last tenth
/// of a second, as Android's VelocityTracker does, and nothing once it has stopped for 40 ms.
struct VelocityTracker {
    private var samples: [(t: Double, p: SIMD2<Double>)] = []

    private static let horizon = 0.1
    private static let stopped = 0.04

    mutating func add(_ p: SIMD2<Double>, at t: Double) {
        samples.append((t, p))
        if samples.count > 20 { samples.removeFirst(samples.count - 20) }
    }

    mutating func reset() { samples.removeAll() }

    /// Points a second.
    var velocity: SIMD2<Double> {
        guard let newest = samples.last else { return .zero }
        // Back from the newest, while each sample is recent and close to the one after it.
        var recent = [newest]
        for s in samples.dropLast().reversed() {
            if newest.t - s.t > Self.horizon || recent[recent.count - 1].t - s.t > Self.stopped { break }
            recent.append(s)
        }
        guard recent.count >= 2 else { return .zero }
        let ts = recent.map { $0.t - newest.t }
        return SIMD2(slope(ts, recent.map { $0.p.x }), slope(ts, recent.map { $0.p.y }))
    }

    /// The rate of change at t = 0 of the least-squares curve through (`ts`, `xs`): a parabola from
    /// three samples on, a line before.
    private func slope(_ ts: [Double], _ xs: [Double]) -> Double {
        if ts.count < 3 {
            let dt = ts[0] - ts[1]
            return dt > 0 ? (xs[0] - xs[1]) / dt : 0
        }
        // Normal equations for x = a + b t + c t².
        var s = [Double](repeating: 0, count: 5), r = [Double](repeating: 0, count: 3)
        for (t, x) in zip(ts, xs) {
            var p = 1.0
            for k in 0..<5 {
                s[k] += p
                if k < 3 { r[k] += p * x }
                p *= t
            }
        }
        let m = [[s[0], s[1], s[2]], [s[1], s[2], s[3]], [s[2], s[3], s[4]]]
        guard let coefficients = solve3(m, r) else {
            let dt = ts[0] - ts[1]
            return dt > 0 ? (xs[0] - xs[1]) / dt : 0
        }
        return coefficients[1]
    }

    private func solve3(_ m: [[Double]], _ r: [Double]) -> [Double]? {
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])
                - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let d = det(m)
        guard abs(d) > 1e-18 else { return nil }
        return (0..<3).map { col in
            var a = m
            for row in 0..<3 { a[row][col] = r[row] }
            return det(a) / d
        }
    }
}

/// Android's LinearOutSlowInEasing, cubic-bezier(0, 0, 0.2, 1): off quickly, settling slowly.
func linearOutSlowIn(_ x: Double) -> Double {
    let x = min(max(x, 0), 1)
    // The curve's x and y for a parameter u, with control points (0, 0) and (0.2, 1).
    func bx(_ u: Double) -> Double { 3 * (1 - u) * u * u * 0.2 + u * u * u }
    func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * 0 + 3 * (1 - u) * u * u + u * u * u }
    var lo = 0.0, hi = 1.0
    for _ in 0..<40 {
        let mid = (lo + hi) / 2
        if bx(mid) < x { lo = mid } else { hi = mid }
    }
    return by((lo + hi) / 2)
}

// MARK: - The orb

/// The orb on the home and done screens, which can be pulled about. It gives a little under the
/// pointer, follows a drag a short way, held back more the further it goes and drawn out toward
/// the pointer; let go, it springs home at the speed it was going, wobbling as the drop does
/// when it lands in a session, and sends out a ring. It can be caught again on its way. With
/// Reduce Motion it still follows the pointer, but goes home without the wobble or the ring.
/// Positions are in points from the orb's place; `side` is its canvas's.
struct OrbPoke {
    /// The furthest it goes however far it is pulled, as a share of its canvas.
    static let reach = 0.35
    /// How far it is drawn out toward the pointer at its furthest.
    static let stretch = 0.32
    /// How much smaller it gets under the pointer.
    static let dent = 0.05
    /// The ring it sends out when let go: how long it lasts, and how far out it gets.
    static let ringSeconds = 1.6
    static let ringSpread = 1.3
    /// Home with a little bounce, as a thing let go of.
    static let home = DampedSpring(damping: 0.55, stiffness: 300)
    /// The drop's wobble as it lands in a session (Drip.swift): 2.4 times a second.
    static let wobble = DampedSpring(damping: 0.28, stiffness: 227)
    /// With Reduce Motion: home without overshooting.
    static let homeStill = DampedSpring(damping: 1, stiffness: 1500)
    /// How long the dent takes to press in.
    static let dentIn = 0.1

    let side: Double
    let still: Bool

    /// Where the pointer has taken it, while the pointer is down.
    private(set) var held: SIMD2<Double>?
    /// The way it was last pulled, in radians.
    private(set) var axis = 0.0
    private var from = SIMD2<Double>.zero
    private var pointer0 = SIMD2<Double>.zero
    private var tracker = VelocityTracker()
    private var pressedAt = -Double.infinity
    private var dentFrom = 0.0
    private var letGoAt = -Double.infinity
    private var letGo = SIMD2<Double>.zero
    private var letGoSpeed = SIMD2<Double>.zero
    private var letGoStretch = 0.0
    private var letGoDent = 0.0
    private(set) var ringAt = -Double.infinity
    private(set) var ringStrength = 0.0
    /// The orb's radius when the ring left it.
    private(set) var ringFrom = 0.0

    init(side: Double, still: Bool) {
        self.side = side
        self.still = still
    }

    private var reach: Double { side * Self.reach }

    /// Pressed with the pointer at `p`. Caught on its way home, it carries on from where it is.
    mutating func down(_ p: SIMD2<Double>, at t: Double) {
        let now = pull(at: t)
        dentFrom = dent(at: t)
        from = unRubberBand(now, limit: reach)
        held = now
        pointer0 = p
        pressedAt = t
        letGoAt = -.infinity
        tracker.reset()
        tracker.add(now, at: t)
    }

    mutating func move(_ p: SIMD2<Double>, at t: Double) {
        guard held != nil else { return }
        let h = rubberBand(from + (p - pointer0), limit: reach)
        held = h
        if norm(h) > 0 { axis = atan2(h.y, h.x) }
        tracker.add(h, at: t)
    }

    /// Let go. `radius` is the orb's radius then, for the ring.
    mutating func up(at t: Double, radius: Double) {
        guard let h = held else { return }
        // Held still before it was let go, it was going nowhere.
        tracker.add(h, at: t)
        letGoDent = dent(at: t)
        letGo = h
        letGoSpeed = tracker.velocity
        letGoStretch = Self.stretch * norm(h) / reach
        letGoAt = t
        held = nil
        if !still {
            ringAt = t
            ringFrom = radius
            ringStrength = 0.16 + 0.16 * norm(h) / reach
        }
    }

    var isHeld: Bool { held != nil }

    /// Where it is from its place.
    func pull(at t: Double) -> SIMD2<Double> {
        if let held { return held }
        guard letGoAt.isFinite, t >= letGoAt else { return .zero }
        let spring = still ? Self.homeStill : Self.home
        let dt = t - letGoAt
        return SIMD2(spring.at(dt, from: letGo.x, speed: letGoSpeed.x).value,
                     spring.at(dt, from: letGo.y, speed: letGoSpeed.y).value)
    }

    /// How far it is drawn out along `axis` (squashed across it to match).
    func stretch(at t: Double) -> Double {
        if let held { return Self.stretch * norm(held) / reach }
        guard letGoAt.isFinite, t >= letGoAt else { return 0 }
        return (still ? Self.homeStill : Self.wobble).at(t - letGoAt, from: letGoStretch, speed: 0).value
    }

    /// How far it has given under the pointer: 1 pressed in, below 0 as it wobbles back out.
    func dent(at t: Double) -> Double {
        if held != nil {
            let k = Self.dentIn > 0 ? linearOutSlowIn((t - pressedAt) / Self.dentIn) : 1
            return dentFrom + (1 - dentFrom) * k
        }
        guard letGoAt.isFinite, t >= letGoAt else { return 0 }
        return (still ? Self.homeStill : Self.wobble).at(t - letGoAt, from: letGoDent, speed: 0).value
    }

    /// The ring at `t`, if one is out: its radius and how strongly it shows.
    func ring(at t: Double) -> (radius: Double, alpha: Double)? {
        let age = t - ringAt
        guard age >= 0, age <= Self.ringSeconds else { return nil }
        let fade = 1 - age / Self.ringSeconds
        return (ringFrom * (1 + Self.ringSpread * (1 - fade * fade)), ringStrength * fade * fade)
    }
}

// MARK: - The session length

/// The session length slid along with the pointer, once its row is open: the chosen colour comes
/// away under the pointer as a bead of the same liquid, running into each drop it passes, and
/// let go it carries on to the drop it was heading for, which is picked. Past the first or last
/// drop it holds back. `x` is along the row from its middle, in points.
struct BeadSlide {
    /// Let go, how far ahead of the bead the drop it carries on to is looked for: as far as it
    /// would go in this long.
    static let projection = 0.1
    /// The bead on its way to a drop: quickly, with the least bounce, as it was thrown.
    static let home = DampedSpring(damping: 0.8, stiffness: 600)
    /// How far the bead runs into the drops it passes, as a share of a drop's size.
    static let reach = 0.4
    /// Within this of its drop, it has arrived.
    static let arrived = 0.5

    let count: Int
    /// From one drop to the next, and a drop's size.
    let step: Double
    let size: Double

    private(set) var held: Double?
    /// The drop the bead is over.
    private(set) var over: Int
    private var start: Double
    private var pointer0: Double
    private var tracker = VelocityTracker()
    private(set) var letGoAt = -Double.infinity
    private var letGo = 0.0
    private(set) var speed = 0.0
    /// The drop it goes to once let go.
    private(set) var target: Int?

    /// Pressed on the drop nearest `pointer`, and slid far enough to mean it.
    init(count: Int, step: Double, size: Double, pointer: Double) {
        self.count = count
        self.step = step
        self.size = size
        let i = min(max(Int((pointer / step + Double(count - 1) / 2).rounded()), 0), count - 1)
        start = step * (Double(i) - Double(count - 1) / 2)
        pointer0 = pointer
        over = i
    }

    func slot(_ i: Int) -> Double { step * (Double(i) - Double(count - 1) / 2) }

    func nearest(_ x: Double) -> Int {
        min(max(Int((x / step + Double(count - 1) / 2).rounded()), 0), count - 1)
    }

    /// Where the bead goes for the pointer `x` along the row from its start: with it between the
    /// first and last drops, and held back past them.
    private func heldAt(_ x: Double) -> Double {
        let first = slot(0), last = slot(count - 1), r = size / 2
        if x < first { return first + rubberBand(x - first, limit: r) }
        if x > last { return last + rubberBand(x - last, limit: r) }
        return x
    }

    /// The pointer moved to `pointer`. True when the bead has come over another drop (a tick).
    @discardableResult
    mutating func move(_ pointer: Double, at t: Double) -> Bool {
        guard target == nil else { return false }
        let b = heldAt(start + pointer - pointer0)
        held = b
        tracker.add(SIMD2(b, 0), at: t)
        speed = tracker.velocity.x
        if nearest(b) != over {
            over = nearest(b)
            return true
        }
        return false
    }

    /// Let go: it carries on the way it was going, to the drop it would come to rest at. Returns
    /// that drop.
    @discardableResult
    mutating func up(at t: Double) -> Int {
        let b = held ?? start
        // Held still before it was let go, it was going nowhere.
        tracker.add(SIMD2(b, 0), at: t)
        speed = tracker.velocity.x
        let aim = min(max(b + speed * Self.projection, slot(0)), slot(count - 1))
        let to = nearest(aim)
        letGo = b
        letGoAt = t
        target = to
        held = nil
        return to
    }

    /// Where the bead is at `t`.
    func bead(at t: Double) -> Double {
        if let held { return held }
        guard let target else { return start }
        return slot(target) + Self.home.at(t - letGoAt, from: letGo - slot(target), speed: speed).value
    }

    /// How fast the bead is going at `t`.
    func beadSpeed(at t: Double) -> Double {
        if held != nil { return speed }
        guard let target else { return 0 }
        return Self.home.at(t - letGoAt, from: letGo - slot(target), speed: speed).velocity
    }

    /// Whether the pointer is still on it: from the press until it is let go.
    var isSliding: Bool { target == nil }

    /// When the bead, let go, reaches its drop.
    var arrivesAt: Double? {
        guard let target else { return nil }
        return letGoAt + Self.home.settles(from: letGo - slot(target), speed: speed, within: Self.arrived)
    }

    /// How much of the bead lies over the drop at `x`, at `t`.
    func under(_ x: Double, at t: Double) -> Double {
        smoothstep(0, 1, 1 - abs(bead(at: t) - x) / size)
    }

    /// The bead drawn out by its speed, as the drops are on the move.
    func beadStretch(at t: Double) -> Double {
        1 + 0.14 * min(1, abs(beadSpeed(at: t)) / step / 13)
    }
}

// MARK: - The volume slider

/// How far the volume slider is stretched past an end: held by the pointer, or springing back
/// once let go. Dragged on past an end, it gives, less the further it goes.
struct Give {
    /// The furthest it stretches past an end.
    static let limit = 8.0
    static let back = DampedSpring(damping: 0.5, stiffness: 500)

    private(set) var held: Double?
    private var tracker = VelocityTracker()
    private var letGoAt = -Double.infinity
    private var letGo = 0.0
    private var letGoSpeed = 0.0

    /// The pointer is `past` points beyond an end (below 0 past the start, 0 between the ends).
    mutating func drag(past: Double, at t: Double) {
        let s = rubberBand(past, limit: Self.limit)
        if held == nil { tracker.reset() }
        held = s
        tracker.add(SIMD2(s, 0), at: t)
    }

    mutating func release(at t: Double) {
        guard let h = held else { return }
        letGo = h
        letGoSpeed = tracker.velocity.x
        letGoAt = t
        held = nil
    }

    func stretch(at t: Double) -> Double {
        if let held { return held }
        guard letGoAt.isFinite, t >= letGoAt else { return 0 }
        return Self.back.at(t - letGoAt, from: letGo, speed: letGoSpeed).value
    }
}

// MARK: - The ✕

/// The ✕ that ends a session when held: it fills at an even pace while held, and ends the session
/// once full, `holdSeconds` from empty; let go too soon, it drains away quickly.
struct HoldFill {
    static let holdSeconds = 1.0
    static let drainSeconds = 0.2

    private var pressedAt: Double?
    private var fromFill = 0.0
    private var drainAt = -Double.infinity
    private var drainFrom = 0.0

    var isHeld: Bool { pressedAt != nil }

    mutating func press(at t: Double) {
        guard pressedAt == nil else { return }
        fromFill = fill(at: t)
        pressedAt = t
    }

    mutating func release(at t: Double) {
        guard pressedAt != nil else { return }
        let f = fill(at: t)
        pressedAt = nil
        drainFrom = f < 1 ? f : 0
        drainAt = t
    }

    /// How full it is at `t`, from 0 to 1.
    func fill(at t: Double) -> Double {
        if let pressedAt { return min(1, fromFill + (t - pressedAt) / Self.holdSeconds) }
        guard drainAt.isFinite, t >= drainAt else { return 0 }
        return drainFrom * (1 - linearOutSlowIn((t - drainAt) / Self.drainSeconds))
    }

    /// When it will be full, while held.
    var fullAt: Double? { pressedAt.map { $0 + (1 - fromFill) * Self.holdSeconds } }
}

private func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

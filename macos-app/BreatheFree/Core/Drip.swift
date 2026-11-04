//
//  Drip.swift
//  BreatheFree
//
//  The opening, during the settle: a drop gathers under the middle of the top of the box,
//  swaying a little in the breeze, necks and lets go, and falls into the middle, where it lands
//  as the orb with a wobble and a ring; the bead it leaves on the line springs back into it.
//  Everything here is in half-sizes of the box from its centre, y down, so the top is at
//  y = -1. Kept in step with the Android app's Drip.kt.
//

import Foundation

/// A drop hanging under the top of the box: from the line at `ax`, with its bulb of radius `rb`
/// centred at (`bx`, `by`), a neck `wn` either side of `ax` where it meets the line, and the
/// neck leaving the bulb `phi` radians either side of its top.
struct Hanging: Equatable {
    let ax: Double
    let bx: Double
    let by: Double
    let rb: Double
    let wn: Double
    let phi: Double
}

/// A falling drop of radius `r` at (`x`, `y`), drawn out `sy` tall and `sx` wide by its speed.
struct Falling: Equatable {
    let x: Double
    let y: Double
    let r: Double
    let sx: Double
    let sy: Double
}

/// One instant of the opening. `orb` is the orb's radius once the drop has landed (0 before),
/// squashed `squash` wider than tall as it wobbles.
struct DripFrame {
    var hanging: Hanging?
    var bead: Hanging?
    var drop: Falling?
    var satellite: Falling?
    var orb = 0.0
    var squash = 0.0
}

enum Drip {
    private static let gathers = 1.8
    private static let gathered = 3.6
    private static let letsGo = 4.15
    private static let fall = 0.42

    /// When the drop lands in the middle of the box.
    static let lands = letsGo + fall

    /// How long the orb takes to swell from the drop to its size for the settle.
    private static let swell = 0.85

    /// The drop's radius once it has gathered.
    private static let r = 0.24
    private static let sway = 0.035

    private static func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func ease(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * clamp(x)) }
    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
    private static func easeIn(_ x: Double) -> Double { clamp(x) * clamp(x) }
    private static func degrees(_ d: Double) -> Double { d * Double.pi / 180 }

    /// How much wider than tall the orb is `tau` seconds after landing: a wobble dying away.
    private static func wobble(_ tau: Double) -> Double {
        tau < 0 ? 0 : 0.26 * exp(-4.2 * tau) * cos(2 * Double.pi * 2.4 * tau)
    }

    /// How far the count on the orb has faded in: it waits for the drop to land.
    static func countAlpha(_ t: Double) -> Double { clamp((t - lands) / 0.6) }

    static func at(_ t: Double) -> DripFrame {
        var f = DripFrame()
        if t >= gathers && t < letsGo {
            // Gathering (g, 0 to 1), then necking (u) until it lets go.
            let g = ease((t - gathers) / (gathered - gathers))
            let u = t < gathered ? 0 : easeIn((t - gathered) / (letsGo - gathered))
            let rb = max(0.012, r * cbrt(g))
            let breeze = sway * sin((t - gathers) * 2.6) * g * (1 - u)
            let yb = rb * lerp(0.35, 1.05, g) + u * 0.2
            let wn = rb * lerp(1.1, 0.75, g) * lerp(1, 0.18, u)
            f.hanging = Hanging(ax: 0, bx: breeze, by: -1 + yb, rb: rb, wn: wn, phi: degrees(lerp(80, 62, g) - 40 * u))
        } else if t >= letsGo {
            let since = t - letsGo
            // The bead left on the line springs back into it.
            if since < 0.8 {
                let rb = r * 0.32 * (1 - easeOut(since / 0.8))
                if rb > 0.004 {
                    let yb = rb * (0.55 + 0.5 * exp(-5 * since) * cos(2 * Double.pi * 3 * since))
                    f.bead = Hanging(ax: 0, bx: 0, by: -1 + yb, rb: rb, wn: rb * 1.1, phi: degrees(85))
                }
            }
            // Falling faster all the way, drawn out by its speed, from where it let go to the middle.
            let from = -1 + r * 1.05 + 0.2
            if t < lands {
                let k = since / fall
                let stretch = 1 + 0.16 * (1 - k) + 0.14 * k
                f.drop = Falling(x: 0, y: from * (1 - k * k), r: r, sx: 1 / stretch.squareRoot(), sy: stretch)
            }
            // A small drop pinched off behind it, following it down.
            let sk = (since - 0.05) / fall
            if sk > 0 && sk < 1 {
                f.satellite = Falling(x: 0, y: (from - r * 0.9) * (1 - sk * sk), r: 0.032, sx: 1, sy: 1)
            }
        }
        if t >= lands {
            f.orb = lerp(r, BoxGeometry.orbMin, easeOut((t - lands) / swell))
            f.squash = wobble(t - lands)
        }
        return f
    }
}

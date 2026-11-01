//
//  Gust.swift
//  BreatheFree
//
//  The session's words as specks of ink on the wind. Kept in step with the Android app's
//  Gust.kt: the same constants, the same paths and the same luck for every speck.
//

import Foundation

/// Which words the wind is carrying at one instant: the one blowing in (or settled) and the one
/// blowing away, each with the seconds since its gust began. Either may be "".
struct GustWords: Equatable {
    let arriving: String
    let arriveSince: Double
    let leaving: String
    let leaveSince: Double
}

/// The words as specks of ink on the wind. Each word is blown in from the left, its left end
/// landing first, and settles under the box; the gust that brings the next word carries it off to
/// the right. The specks stay in a band round the words, so the wind passes under the box and orb
/// rather than across them; a few rise into place out of the clear sky below the words and sink
/// back into it as they go. Everything is a function of session time, like the rest of the
/// screen, so a paused session holds the specks where they are.
enum Gust {
    /// A word starts blowing in this long before its phase, so it can be read just after the phase begins...
    static let arriveLead = 0.5

    /// ...and starts blowing away this long before the next, a moment ahead of the next word.
    static let leaveLead = 0.8

    /// How long one speck takes to come in from the left, and to go off to the right.
    static let arriveSeconds = 0.9
    static let leaveSeconds = 1.0

    /// How much later the right end of a word sets off than the left, and each speck's own lag on
    /// top: more of it leaving, so the wind takes a word apart rather than sliding it off whole.
    static let arriveStagger = 0.25
    static let arriveScatter = 0.15
    static let leaveStagger = 0.25
    static let leaveScatter = 0.3

    /// Seconds from a word's gust to its last speck landing, and to its last speck gone.
    static let arrived = arriveStagger + arriveScatter + arriveSeconds
    static let gone = leaveStagger + leaveScatter + leaveSeconds

    /// Each speck's own pace: up to this much quicker than the slowest, so specks overtake one
    /// another rather than keeping step.
    static let pace = 0.12

    /// How far a speck strays from its line while it is in the air, on slow gusts of its own: a
    /// share of the window's width along the wind, and points across it, little enough to keep
    /// under the box.
    static let wander = 0.02
    static let wanderAcross = 5.0

    /// The share of specks that take the low road: up out of the clear sky from the lower left,
    /// and down into it to the lower right, each to its own depth.
    static let low = 0.25

    /// How far a settled word swells with full lungs.
    static let swell = 0.03

    /// Where one speck is, from the word's centre (y down), and how much of it shows, 0...1.
    ///
    /// `tx`, `ty` is where it belongs in the word, `along` how far across the word that is (0 the
    /// left end, 1 the right), and `seed` picks its own path. `arriveSince` is the seconds since
    /// its word started blowing in, `leaveSince` since it started blowing away (negative until
    /// then). `reach` is how far the wind carries it, the window's width, and `room` how far below
    /// the words the sky is clear; `unit` is one point; `level` is how full the lungs are, and `t`
    /// session time, for the settled specks' shimmer.
    static func place(tx: Double, ty: Double, along: Double, seed: Int,
                      arriveSince: Double, leaveSince: Double,
                      reach: Double, room: Double, unit: Double, level: Double, t: Double) -> (x: Double, y: Double, alpha: Double) {
        let swell = 1 + Self.swell * level
        var x = tx * swell
        var y = ty * swell

        // In from the left, out of a band a little above the words to a little below them,
        // swirling as it comes and steadying as it lands.
        let inDelay = along * arriveStagger + luck(seed, 0) * arriveScatter
        let q = clamp((arriveSince - inDelay) / (arriveSeconds * (1 - pace * luck(seed, 13))))
        let e = easeOut(q)
        let left = 1 - e
        let swirl = left * 6 * unit
        x -= left * reach * (0.55 + 0.35 * luck(seed, 1))
        y += left * unit * (-10 + 50 * luck(seed, 2))
        y += sin(.pi * e) * (luck(seed, 3) - 0.5) * 24 * unit
        x += sin(t * 3 + luck(seed, 4) * tau) * swirl
        y += cos(t * 2.3 + luck(seed, 5) * tau) * swirl
        // Taking the low road, it comes up from below as it closes in, rising into place.
        let low = max(0, (luck(seed, 19) - (1 - Self.low)) / Self.low) * room
        y += low * (1 - q) * (1 - q)
        var alpha = smoothstep(0, 0.35, q)
        // Off its line until it is nearly down, so the specks don't come in on rails.
        var stray = 1 - smoothstep(0.3, 1, q)

        // Settled, it stirs a little, as snow does in a breeze.
        x += sin(t * 1.7 + luck(seed, 6) * 9) * 0.25 * unit
        y += cos(t * 1.3 + luck(seed, 7) * 9) * 0.25 * unit

        // Off to the right, the left end of the word first, gathering speed and swirling as it goes.
        if leaveSince > 0 {
            let outDelay = along * leaveStagger + luck(seed, 8) * leaveScatter
            let p = clamp((leaveSince - outDelay) / (leaveSeconds * (1 - pace * luck(seed, 14))))
            // Moving off at once and swirling only as it picks up speed, so no letter shivers in place first.
            let g = p * p
            let gusting = min(1, 3 * g) * 6 * unit
            x += g * reach * (0.5 + 0.4 * luck(seed, 1)) + sin(t * 3 + luck(seed, 4) * tau) * gusting
            y += g * unit * (-10 + 36 * luck(seed, 9)) + cos(t * 2.3 + luck(seed, 5) * tau) * gusting
            // On the low road it sinks as it goes, down and away to the lower right.
            y += low * pow(p, 1.5)
            alpha *= 1 - smoothstep(0.35, 1, p)
            stray += smoothstep(0, 0.6, p)
        }

        if stray > 0 {
            x += stray * wander * reach * sin(t * (1.5 + 2 * luck(seed, 15)) + luck(seed, 16) * tau)
            y += stray * wanderAcross * unit * sin(t * (1.5 + 2 * luck(seed, 17)) + luck(seed, 18) * tau)
        }
        return (x, y, alpha)
    }

    /// A speck's own number `k`, 0...1: the same every time for the same speck, and the same as
    /// the Android app's for the same seed.
    static func luck(_ seed: Int, _ k: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: seed) &* 0x9E37_79B9 &+ UInt32(truncatingIfNeeded: k) &* 0x85EB_CA77
        h = (h ^ (h >> 16)) &* 0x85EB_CA6B
        h = (h ^ (h >> 13)) &* 0xC2B2_AE35
        h ^= h >> 16
        return Double(h >> 8) / 16_777_216
    }

    private static let tau = 2 * Double.pi

    private static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }

    private static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    private static func smoothstep(_ a: Double, _ b: Double, _ v: Double) -> Double {
        let x = clamp((v - a) / (b - a))
        return x * x * (3 - 2 * x)
    }
}

extension SessionPlan {
    /// The words on the wind at session time `t`: each word blows in `Gust.arriveLead` before its
    /// own words come up and away `Gust.leaveLead` before the next ones do, so for a moment before
    /// each change only the leaving word is in the air.
    func gust(at t: Double) -> GustWords {
        let coming = prompt(at: t + Gust.arriveLead)
        let going = prompt(at: t + Gust.leaveLead)
        // Between the two leads, the words coming up have begun to leave and the next are not on their way yet.
        let between = coming.since > going.since
        return GustWords(
            arriving: between ? "" : coming.text,
            arriveSince: between ? 0 : coming.since,
            leaving: going.previous,
            leaveSince: going.since
        )
    }
}

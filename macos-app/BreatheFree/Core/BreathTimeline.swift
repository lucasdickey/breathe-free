//
//  BreathTimeline.swift
//  BreatheFree
//
//  Everything about a session that depends only on elapsed time. The picture and the
//  sound are both computed from this, so they cannot disagree. Kept in step with the
//  Android app's BreathTimeline.kt.
//

import Foundation

/// The four sides of the box, in the order they are breathed.
enum Phase: Int, CaseIterable {
    case inhale, holdFull, exhale, holdEmpty

    var prompt: String {
        switch self {
        case .inhale: return "Breathe in"
        case .holdFull, .holdEmpty: return "Hold"
        case .exhale: return "Breathe out"
        }
    }
}

enum Stage {
    case settle, breathing, complete
}

/// The words on screen at one instant, the words before them and the seconds since they
/// changed, so the screen can cross from one to the other as a function of session time,
/// like everything else it draws.
struct Prompt: Equatable {
    static let fadeSeconds = 0.35

    let text: String
    let previous: String
    let since: Double

    /// How far the cross has gone: 0 showing `previous`, 1 showing `text`.
    var fade: Double {
        let x = min(max(since / Self.fadeSeconds, 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// Everything the screen shows at one instant of a session.
struct BreathFrame {
    let stage: Stage
    /// Nil while settling and once complete.
    let phase: Phase?
    /// Phases begun since breathing started: -1 while settling, phaseCount once complete.
    let phaseIndex: Int
    /// Seconds into the current phase (or into the settle, or since completion).
    let phaseElapsed: Double
    /// 0...1 through the current phase, or through the settle.
    let progress: Double
    /// How full the lungs are: 0 empty, 1 full. Drives the orb, the dot and the sound.
    let level: Double
    /// 0-based cycle number.
    let cycle: Int
    /// Whole seconds left in the phase: 4...1 (8...1 while settling).
    let countdown: Int
    /// Breathing seconds left, not counting the settle.
    let remaining: Double

    /// Which side of the box the dot is on: 0 left going up, 1 top going right,
    /// 2 right going down, 3 bottom going left.
    var boxSide: Int { stage == .breathing ? phaseIndex % 4 : 0 }

    /// How far along that side, 0...1. On the two moving sides the dot rises and falls
    /// with the breath itself, so its height always matches the orb.
    var boxFraction: Double {
        switch phase {
        case .inhale?, .exhale?: return BreathCurve.rise(progress)
        case .holdFull?, .holdEmpty?: return progress
        case nil: return 0
        }
    }
}

/// The shape of one breath.
enum BreathCurve {
    // Below 1 the motion gets going a little sooner after the cue than a plain sine
    // would, while still starting and ending at rest.
    private static let skew = 0.8

    /// Lung level across an inhale, 0 → 1. An exhale is 1 - rise(p).
    static func rise(_ p: Double) -> Double {
        let q = pow(min(max(p, 0), 1), skew)
        return 0.5 - 0.5 * cos(Double.pi * q)
    }

    /// How much air is moving across an inhale or exhale: 0 at both ends, peak just before the middle.
    static func flow(_ p: Double) -> Double {
        let q = pow(min(max(p, 0), 1), skew)
        return sin(Double.pi * q)
    }
}

/// A session laid out on one time axis, starting at 0 when Begin is pressed: an 8 second
/// settle, then `cycles` rounds of in-4, hold-4, out-4, hold-4.
struct SessionPlan: Equatable {
    static let settleSeconds = 8.0
    static let phaseSeconds = 4.0
    static let cycleSeconds = phaseSeconds * 4
    /// How long the closing chord rings after the last hold.
    static let closingSeconds = 8.0
    static let settlePrompt = "Settle in"
    static let cycleChoices = [2, 6, 10, 20, 36, 50]
    static let defaultCycles = 10

    let cycles: Int

    init(cycles: Int) {
        precondition(cycles > 0, "cycles must be positive")
        self.cycles = cycles
    }

    var breathingSeconds: Double { Double(cycles) * Self.cycleSeconds }

    /// Session time at which the last hold ends.
    var endTime: Double { Self.settleSeconds + breathingSeconds }

    var phaseCount: Int { cycles * 4 }

    func phaseStart(_ index: Int) -> Double { Self.settleSeconds + Double(index) * Self.phaseSeconds }

    func frame(at t: Double) -> BreathFrame {
        if t < Self.settleSeconds {
            let e = max(0, t)
            return BreathFrame(
                stage: .settle, phase: nil, phaseIndex: -1, phaseElapsed: e,
                progress: e / Self.settleSeconds, level: 0, cycle: 0,
                countdown: Self.wholeSecondsLeft(Self.settleSeconds - e, of: Self.settleSeconds),
                remaining: breathingSeconds
            )
        }
        let tb = t - Self.settleSeconds
        if tb >= breathingSeconds {
            return BreathFrame(
                stage: .complete, phase: nil, phaseIndex: phaseCount,
                phaseElapsed: tb - breathingSeconds, progress: 1, level: 0, cycle: cycles,
                countdown: 0, remaining: 0
            )
        }
        let index = min(phaseCount - 1, Int((tb / Self.phaseSeconds).rounded(.down)))
        let elapsed = tb - Double(index) * Self.phaseSeconds
        let p = min(max(elapsed / Self.phaseSeconds, 0), 1)
        let phase = Phase(rawValue: index % 4)!
        let level: Double
        switch phase {
        case .inhale: level = BreathCurve.rise(p)
        case .holdFull: level = 1
        case .exhale: level = 1 - BreathCurve.rise(p)
        case .holdEmpty: level = 0
        }
        return BreathFrame(
            stage: .breathing, phase: phase, phaseIndex: index, phaseElapsed: elapsed,
            progress: p, level: level, cycle: index / 4,
            countdown: Self.wholeSecondsLeft(Self.phaseSeconds - elapsed, of: Self.phaseSeconds),
            remaining: breathingSeconds - tb
        )
    }

    /// "Settle in", then each phase's words, then nothing once the session is complete.
    func prompt(at t: Double) -> Prompt {
        let f = frame(at: t)
        switch f.stage {
        case .settle:
            return Prompt(text: Self.settlePrompt, previous: "", since: f.phaseElapsed)
        case .breathing:
            let previous = f.phaseIndex == 0 ? Self.settlePrompt : Phase(rawValue: (f.phaseIndex - 1) % 4)!.prompt
            return Prompt(text: f.phase!.prompt, previous: previous, since: f.phaseElapsed)
        case .complete:
            return Prompt(text: "", previous: Phase(rawValue: (phaseCount - 1) % 4)!.prompt, since: f.phaseElapsed)
        }
    }

    // 4.0 → 4, 3.5 → 4, 3.0 → 3, ... 0.2 → 1. The epsilon keeps 3.0000000001 from reading 4.
    private static func wholeSecondsLeft(_ left: Double, of full: Double) -> Int {
        min(max(Int((left - 1e-9).rounded(.up)), 1), Int(full))
    }
}

/// The box the dot travels around: a rounded square, walked clockwise from the bottom-left
/// corner. Every side is the same length (half a corner, a straight, half a corner), so
/// side + fraction also measures the whole outline in quarters.
enum BoxGeometry {
    /// Screen position (y down) of a point `f` (0...1) along `side`, on a square centred at
    /// (cx, cy) with half-size `h` and corner radius `r`.
    static func point(side: Int, f: Double, cx: Double, cy: Double, h: Double, r: Double) -> (x: Double, y: Double) {
        let arc = Double.pi * r / 4
        let straight = 2 * (h - r)
        let d = min(max(f, 0), 1) * (straight + 2 * arc)
        let c = h - r
        // Side 0 in y-up coordinates: half of the bottom-left corner, up the left edge,
        // half of the top-left corner.
        var x: Double
        var y: Double
        if d <= arc {
            let a = 1.25 * Double.pi - d / r
            x = -c + r * cos(a)
            y = -c + r * sin(a)
        } else if d <= arc + straight {
            x = -h
            y = -c + (d - arc)
        } else {
            let a = Double.pi - (d - arc - straight) / r
            x = -c + r * cos(a)
            y = c + r * sin(a)
        }
        // The other sides are the same walk turned clockwise by a quarter each.
        for _ in 0..<(((side % 4) + 4) % 4) {
            let nx = y
            y = -x
            x = nx
        }
        return (cx + x, cy - y)
    }

    /// How fast a ring spreads from the orb, in half-sizes of the box per second.
    static let ripplePace = 0.3

    /// How long a ring that leaves an orb of radius `start` takes to reach the sides of a box of
    /// half-size `h`. It ends there, fading out on the way, so it never spreads past the box.
    static func rippleSeconds(start: Double, h: Double) -> Double {
        max(0, (h - start) / (h * ripplePace))
    }

    /// That ring's radius `age` seconds after it left the orb.
    static func rippleRadius(start: Double, age: Double, h: Double) -> Double {
        min(h, start + age * h * ripplePace)
    }
}

/// A session in progress: its plan and the host time, in seconds (CACurrentMediaTime in the
/// app), at which its time is zero. While paused, its time stands still at `pausedAt`.
struct ActiveSession: Equatable {
    let plan: SessionPlan
    let startTime: Double
    /// The host time it was paused at; nil while it runs.
    var pausedAt: Double? = nil

    var isPaused: Bool { pausedAt != nil }

    /// Session time at host time `host`: the seconds since the start, less any time paused.
    func time(at host: Double) -> Double { (pausedAt ?? host) - startTime }

    /// The same session held still at `host`. Pausing a paused session changes nothing.
    func paused(at host: Double) -> ActiveSession {
        guard pausedAt == nil else { return self }
        return ActiveSession(plan: plan, startTime: startTime, pausedAt: host)
    }

    /// Carries on from where it was held: the start moves later by the time spent paused, so
    /// the session picks up at the moment it stopped. Resuming a running session changes nothing.
    func resumed(at host: Double) -> ActiveSession {
        guard let held = pausedAt else { return self }
        return ActiveSession(plan: plan, startTime: startTime + (host - held))
    }
}

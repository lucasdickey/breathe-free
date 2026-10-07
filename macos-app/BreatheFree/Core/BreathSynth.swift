//
//  BreathSynth.swift
//  BreatheFree
//
//  The session's sound, generated sample by sample from session time. A line-for-line
//  match of the Android app's BreathSynth.kt, so both apps sound the same.
//

import Foundation

enum SoundMode: String, CaseIterable {
    case ambient, bells, silent

    var label: String {
        switch self {
        case .ambient: return "Ambient"
        case .bells: return "Bells only"
        case .silent: return "Silent"
        }
    }
}

/// Nothing here is a recording. Every layer is computed from the same breath curve the
/// picture uses, so a swell cannot land early or late and nothing is stretched to fit.
///
/// - Pad: a low D drone (D2, D3, A3) under F#4 and A4, the same chord every cycle, blooming
///   as the lungs fill. It all sits below about 1 kHz, and no two voices beat faster than
///   once every few seconds.
/// - Air: soft filtered noise that moves only while air moves: rising and brightening on
///   the inhale, falling and darkening on the exhale, silent during holds.
/// - Bells: soft-mallet tones exactly on each phase change, one pitch per side of the box.
///
/// Every cycle sounds the same, so the breath can settle into it: every pitch and every slow
/// beat between voices is a whole number of sixteenths of a hertz, so the pad comes round
/// exactly once a cycle, and the air's noise is worked out from where in the cycle it is
/// heard, so each breath's air is the same as the last.
///
/// `render` runs only on the audio thread and never allocates or locks. `mode`, `volume`
/// and `fadeOut()` may be used from any thread; they are read once per control step.
final class BreathSynth {
    var mode: SoundMode = .ambient
    /// 0...1, as on a slider.
    var volume: Double = 1.0
    /// True once the closing chord has died away, or a requested fade-out has finished.
    private(set) var finished = false
    private var fadeOutRequested = false

    /// Fade to silence over a third of a second; `finished` turns true when done.
    func fadeOut() { fadeOutRequested = true }

    /// Called on the audio thread as each cue's bells start, with the cue kind (0...3 the
    /// phase, then welcome and closing), its scheduled time and the session time of the
    /// sample it starts on. This is where spoken prompts will hook in.
    var onCue: ((_ kind: Int, _ scheduled: Double, _ actual: Double) -> Void)?

    /// For tests: hear one layer only (0 pad, 1 air, 2 bells), whatever the mode.
    var solo = -1

    private let sampleRate: Double
    private let plan: SessionPlan
    private let dt: Double

    // Session time of the next sample. It advances one sample per sample, at a rate nudged
    // by at most maxNudge to follow the time the platform says each block will be heard,
    // and jumps only after a real gap (a dropout, a new output device).
    private var clock = 0.0
    private var rate = 1.0
    private var anchored = false
    private var startFadeSeconds = BreathSynth.startFadeFromZero

    // Control-rate state. Targets are worked out every `control` samples and every gain
    // glides linearly to its target across the block, so nothing steps.
    private var controlLeft = 0
    private let noteGain: UnsafeMutablePointer<Double>
    private let noteGainStep: UnsafeMutablePointer<Double>
    private let harm: UnsafeMutablePointer<Double>
    private let harmStep: UnsafeMutablePointer<Double>
    private var airGain = 0.0
    private var airGainStep = 0.0
    private var bellGain = 0.0
    private var bellGainStep = 0.0
    private var master = 0.0
    private var masterStep = 0.0
    private var padMix = 0.0
    private var airMix = 0.0
    private var bellMix = 0.0
    private var volMix = -1.0
    private var fadeOutGain = 1.0
    private var startGain = 0.0
    private var airCutoff = 400.0
    private let mixCoef: Double
    private let volCoef: Double

    // Pad oscillators: per note a centre voice plus a slightly flat copy on the left and a
    // slightly sharp copy on the right. Phases are 0...1 turns.
    private let phC: UnsafeMutablePointer<Double>
    private let phL: UnsafeMutablePointer<Double>
    private let phR: UnsafeMutablePointer<Double>
    private let incC: UnsafeMutablePointer<Double>
    private let incL: UnsafeMutablePointer<Double>
    private let incR: UnsafeMutablePointer<Double>

    // Air: one independent noise channel per ear, so it feels wide rather than centred.
    private var airLeft: AirChannel
    private var airRight: AirChannel
    private var svf = Svf()
    private let cycleSamples: Int

    // Bells: a small pool of voices, each four decaying partials.
    private let bellActive: UnsafeMutablePointer<Bool>
    private let bellDelay: UnsafeMutablePointer<Int>
    private let bellAge: UnsafeMutablePointer<Int>
    private let bellAmp: UnsafeMutablePointer<Double>
    private let bellPhase: UnsafeMutablePointer<Double>
    private let bellInc: UnsafeMutablePointer<Double>
    private let bellEnv: UnsafeMutablePointer<Double>
    private let partialMult: UnsafeMutablePointer<Double>
    private let attackSamples: Int
    private let lifeSamples: Int
    private let releaseSamples: Int

    // Cues: the bell for every phase change, in time order.
    private let cueTimes: UnsafeMutablePointer<Double>
    private let cueKinds: UnsafeMutablePointer<Int>
    private let cueCount: Int
    private var nextCue = 0
    private var nextCueTime: Double

    private let table = BreathSynth.sineTable

    init(sampleRate: Double, plan: SessionPlan, seed: UInt32 = 0x5EED) {
        self.sampleRate = sampleRate
        self.plan = plan
        dt = 1.0 / sampleRate
        let n = Self.notes.count
        func doubles(_ count: Int, _ value: (Int) -> Double = { _ in 0 }) -> UnsafeMutablePointer<Double> {
            let p = UnsafeMutablePointer<Double>.allocate(capacity: count)
            for i in 0..<count { p[i] = value(i) }
            return p
        }
        noteGain = doubles(n)
        noteGainStep = doubles(n)
        harm = doubles(n)
        harmStep = doubles(n)
        let dt = 1.0 / sampleRate
        phC = doubles(n)
        phL = doubles(n)
        phR = doubles(n)
        incC = doubles(n) { Self.notes[$0] * dt }
        incL = doubles(n) { (Self.notes[$0] - Self.detune[$0]) * dt }
        incR = doubles(n) { (Self.notes[$0] + Self.detune[$0]) * dt }
        mixCoef = 1 - exp(-Double(Self.control) * dt / 0.25)
        volCoef = 1 - exp(-Double(Self.control) * dt / 0.06)

        airLeft = AirChannel(sampleRate: sampleRate)
        airRight = AirChannel(sampleRate: sampleRate)
        cycleSamples = Int((SessionPlan.cycleSeconds * sampleRate).rounded())

        func ints(_ count: Int) -> UnsafeMutablePointer<Int> {
            let p = UnsafeMutablePointer<Int>.allocate(capacity: count)
            p.initialize(repeating: 0, count: count)
            return p
        }
        let voices = Self.maxBells * Self.partials
        let active = UnsafeMutablePointer<Bool>.allocate(capacity: Self.maxBells)
        active.initialize(repeating: false, count: Self.maxBells)
        bellActive = active
        bellDelay = ints(Self.maxBells)
        bellAge = ints(Self.maxBells)
        bellAmp = doubles(Self.maxBells)
        bellPhase = doubles(voices)
        bellInc = doubles(voices)
        bellEnv = doubles(voices)
        partialMult = doubles(Self.partials) { exp(-1.0 / (Self.partialDecay[$0] * sampleRate)) }
        attackSamples = Int(Self.bellAttack * sampleRate)
        lifeSamples = Int(Self.bellLife * sampleRate)
        releaseSamples = Int(Self.bellRelease * sampleRate)

        let count = plan.phaseCount + 2
        let times = doubles(count)
        let kinds = ints(count)
        times[0] = Self.welcomeAt
        kinds[0] = Self.cueWelcome
        for i in 0..<plan.phaseCount {
            times[i + 1] = plan.phaseStart(i)
            kinds[i + 1] = i % 4
        }
        times[count - 1] = plan.endTime
        kinds[count - 1] = Self.cueClosing
        cueCount = count
        cueTimes = times
        cueKinds = kinds
        nextCueTime = times[0]

        // Start the oscillators at scattered phases so the first notes don't all line up.
        var s = seed | 1
        for k in 0..<n {
            s = Self.xorshift(s); phC[k] = Self.unit(s)
            s = Self.xorshift(s); phL[k] = Self.unit(s)
            s = Self.xorshift(s); phR[k] = Self.unit(s)
        }
    }

    deinit {
        for p in [noteGain, noteGainStep, harm, harmStep, phC, phL, phR, incC, incL, incR,
                  bellAmp, bellPhase, bellInc, bellEnv, partialMult, cueTimes] {
            p.deallocate()
        }
        bellActive.deallocate()
        bellDelay.deallocate()
        bellAge.deallocate()
        cueKinds.deallocate()
    }

    /// Fills `frames` samples of each channel. `startTime` is the session time at which the
    /// first of them will be heard.
    func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int, startTime: Double) {
        follow(startTime)
        var i = 0
        while i < frames {
            if controlLeft == 0 { control() }
            let n = min(controlLeft, frames - i)
            renderSamples(left: left, right: right, offset: i, count: n)
            i += n
            controlLeft -= n
        }
    }

    private func follow(_ target: Double) {
        if !anchored {
            anchored = true
            clock = target
            // Joining mid-session (sound switched on part way) fades in gently rather than
            // starting the pad at full level.
            startFadeSeconds = target > 1 ? Self.startFadeMidway : Self.startFadeFromZero
            skipCues(before: target - Self.staleCue)
            return
        }
        let drift = target - clock
        if abs(drift) > Self.snapSeconds {
            clock = target
            rate = 1
            skipCues(before: target - Self.staleCue)
        } else {
            rate = 1 + min(max(drift / Self.catchUpSeconds, -Self.maxNudge), Self.maxNudge)
        }
    }

    private func skipCues(before t: Double) {
        while nextCue < cueCount && cueTimes[nextCue] < t { nextCue += 1 }
        nextCueTime = nextCue < cueCount ? cueTimes[nextCue] : .infinity
    }

    private func control() {
        controlLeft = Self.control
        let step = Double(Self.control) * dt * rate
        let t = clock + step // targets are for the end of this block

        // Where the breath is.
        let tb = t - SessionPlan.settleSeconds
        var level = 0.0
        var air = 0.0
        if tb >= 0 && tb < plan.breathingSeconds {
            let index = min(plan.phaseCount - 1, Int((tb / SessionPlan.phaseSeconds).rounded(.down)))
            let p = min(max((tb - Double(index) * SessionPlan.phaseSeconds) / SessionPlan.phaseSeconds, 0), 1)
            switch index % 4 {
            case 0:
                level = BreathCurve.rise(p)
                air = BreathCurve.flow(p) * Self.airInhale
                airCutoff = 300 + 1100 * BreathCurve.rise(p)
            case 1:
                level = 1
            case 2:
                level = 1 - BreathCurve.rise(p)
                air = BreathCurve.flow(p) * Self.airExhale
                airCutoff = 1150 - 850 * BreathCurve.rise(p)
            default:
                level = 0
            }
        }

        // Which layers the listener wants.
        let m = mode
        let wantPad = solo >= 0 ? solo == 0 : m == .ambient
        let wantAir = solo >= 0 ? solo == 1 : m == .ambient
        let wantBells = solo >= 0 ? solo == 2 : m != .silent
        padMix += ((wantPad ? 1 : 0) - padMix) * mixCoef
        airMix += ((wantAir ? 1 : 0) - airMix) * mixCoef
        bellMix += ((wantBells ? 1 : 0) - bellMix) * mixCoef
        let v = min(max(volume, 0), 1)
        let volTarget = v * v
        volMix = volMix < 0 ? volTarget : volMix + (volTarget - volMix) * volCoef

        // Pad.
        let padEnv = padEnvelope(t)
        let n = Self.notes.count
        let pedalBloom = 0.86 + 0.14 * level
        let upperBloom = 0.38 + 0.62 * level
        let padScale = padEnv * padMix
        let blocks = Double(Self.control)
        for k in 0..<n {
            let target: Double
            let harmTarget: Double
            if k < Self.pedalCount {
                target = padScale * Self.baseGain[k] * pedalBloom
                harmTarget = Self.pedalHarmonic[k] * (0.6 + 0.4 * level)
            } else {
                target = padScale * Self.baseGain[k] * upperBloom
                harmTarget = 0.05 + 0.15 * level
            }
            noteGainStep[k] = (target - noteGain[k]) / blocks
            harmStep[k] = (harmTarget - harm[k]) / blocks
        }

        // Air and bells.
        airGainStep = (air * Self.airLevel * airMix - airGain) / blocks
        svf.tune(cutoff: airCutoff, q: Self.airQ, sampleRate: sampleRate)
        bellGainStep = (bellMix * Self.bellLevel - bellGain) / blocks

        // Master: volume, the start fade and any requested fade-out.
        startGain = min(1, startGain + blocks * dt / startFadeSeconds)
        if fadeOutRequested {
            fadeOutGain = max(0, fadeOutGain - blocks * dt / Self.fadeOutSeconds)
        }
        masterStep = (volMix * startGain * fadeOutGain - master) / blocks

        if (fadeOutRequested && fadeOutGain == 0 && master < 1e-6) ||
            t > plan.endTime + SessionPlan.closingSeconds {
            finished = true
        }
    }

    private func padEnvelope(_ t: Double) -> Double {
        let outStart = plan.endTime + 1
        if t <= 0 { return 0 }
        if t < Self.padFadeIn { return Self.raised(t / Self.padFadeIn) }
        if t < outStart { return 1 }
        if t < outStart + Self.padFadeOut { return 1 - Self.raised((t - outStart) / Self.padFadeOut) }
        return 0
    }

    private func renderSamples(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, offset: Int, count: Int) {
        let tick = dt * rate
        let n = Self.notes.count
        let side = Self.side
        let gainOut = Self.outputGain
        let partials = Self.partials
        for i in 0..<count {
            while clock + tick / 2 >= nextCueTime {
                if clock - nextCueTime <= Self.staleCue {
                    startCue(cueKinds[nextCue])
                    onCue?(cueKinds[nextCue], nextCueTime, clock)
                }
                nextCue += 1
                nextCueTime = nextCue < cueCount ? cueTimes[nextCue] : .infinity
            }

            // Pad.
            var padL = 0.0
            var padR = 0.0
            for k in 0..<n {
                let c = phC[k]
                var c2 = c + c
                if c2 >= 1 { c2 -= 1 }
                let body = sine(c) + harm[k] * sine(c2)
                let g = noteGain[k]
                padL += g * (body + side * sine(phL[k]))
                padR += g * (body + side * sine(phR[k]))
                phC[k] = Self.wrap(c + incC[k])
                phL[k] = Self.wrap(phL[k] + incL[k])
                phR[k] = Self.wrap(phR[k] + incR[k])
                noteGain[k] += noteGainStep[k]
                harm[k] += harmStep[k]
            }

            // Air: the same noise at the same place in every cycle.
            var k = Int(((clock - SessionPlan.settleSeconds) * sampleRate).rounded()) % cycleSamples
            if k < 0 { k += cycleSamples }
            let airL = svf.left(airLeft.next(Self.noise(2 * k))) * airGain
            let airR = svf.right(airRight.next(Self.noise(2 * k + 1))) * airGain
            airGain += airGainStep

            // Bells.
            var bell = 0.0
            for b in 0..<Self.maxBells {
                if !bellActive[b] { continue }
                if bellDelay[b] > 0 {
                    bellDelay[b] -= 1
                    continue
                }
                var s = 0.0
                let base = b * partials
                for p in 0..<partials {
                    let j = base + p
                    s += sine(bellPhase[j]) * bellEnv[j]
                    bellPhase[j] = Self.wrap(bellPhase[j] + bellInc[j])
                    bellEnv[j] *= partialMult[p]
                }
                let age = bellAge[b]
                let shape: Double
                if age < attackSamples {
                    shape = 0.5 - 0.5 * cos(Double.pi * Double(age) / Double(attackSamples))
                } else if age > lifeSamples - releaseSamples {
                    shape = Double(lifeSamples - age) / Double(releaseSamples)
                } else {
                    shape = 1
                }
                bell += s * bellAmp[b] * shape
                bellAge[b] = age + 1
                if age + 1 >= lifeSamples { bellActive[b] = false }
            }
            bell *= bellGain
            bellGain += bellGainStep

            let m = master
            master += masterStep
            let j = offset + i
            if finished {
                left[j] = 0
                right[j] = 0
            } else {
                left[j] = Float(Self.soften((padL + airL + bell) * m * gainOut))
                right[j] = Float(Self.soften((padR + airR + bell) * m * gainOut))
            }
            clock += tick
        }
    }

    private func startCue(_ kind: Int) {
        let notes = Self.cueNotes[kind]
        var n = 0
        while n < notes.count {
            startBell(freq: notes[n], amp: notes[n + 1], delaySeconds: notes[n + 2])
            n += 3
        }
    }

    private func startBell(freq: Double, amp: Double, delaySeconds: Double) {
        // A free voice, or else the oldest one (by then it is a faint tail).
        var slot = -1
        var oldest = -1
        for b in 0..<Self.maxBells {
            if !bellActive[b] {
                slot = b
                break
            }
            if oldest < 0 || bellAge[b] > bellAge[oldest] { oldest = b }
        }
        if slot < 0 { slot = oldest }
        bellActive[slot] = true
        bellDelay[slot] = Int(delaySeconds * sampleRate)
        bellAge[slot] = 0
        bellAmp[slot] = amp
        let base = slot * Self.partials
        for p in 0..<Self.partials {
            bellPhase[base + p] = 0
            bellInc[base + p] = freq * Self.partialRatio[p] * dt
            bellEnv[base + p] = Self.partialAmp[p]
        }
    }

    /// Sine of a phase in turns (0...1), from a table with linear interpolation.
    @inline(__always)
    private func sine(_ phase: Double) -> Double {
        let x = phase * Double(Self.tableSize)
        let i = Int(x)
        let f = x - Double(i)
        let a = table[i]
        return a + (table[i + 1] - a) * f
    }

    /// White noise made pink-ish with the rumble taken out; filtered per ear by the shared `Svf` tuning.
    private struct AirChannel {
        private var b0 = 0.0
        private var b1 = 0.0
        private var b2 = 0.0
        private var hpX = 0.0
        private var hpY = 0.0
        private let hpA: Double

        init(sampleRate: Double) {
            let rc = 1 / (2 * Double.pi * BreathSynth.airHighpass)
            hpA = rc / (rc + 1 / sampleRate)
        }

        mutating func next(_ white: Double) -> Double {
            // Paul Kellet's economy pinking filter.
            b0 = 0.99765 * b0 + white * 0.0990460
            b1 = 0.96300 * b1 + white * 0.2965164
            b2 = 0.57000 * b2 + white * 1.0526913
            let pink = (b0 + b1 + b2 + white * 0.1848) * 0.11
            hpY = hpA * (hpY + pink - hpX)
            hpX = pink
            return hpY
        }
    }

    /// Two-pole low-pass (topology-preserving state-variable filter), one state per ear.
    private struct Svf {
        private var a1 = 0.0
        private var a2 = 0.0
        private var a3 = 0.0
        private var l1 = 0.0
        private var l2 = 0.0
        private var r1 = 0.0
        private var r2 = 0.0

        mutating func tune(cutoff: Double, q: Double, sampleRate: Double) {
            let g = tan(Double.pi * min(max(cutoff, 20), sampleRate * 0.45) / sampleRate)
            let k = 1 / q
            a1 = 1 / (1 + g * (g + k))
            a2 = g * a1
            a3 = g * a2
        }

        mutating func left(_ x: Double) -> Double {
            let v3 = x - l2
            let v1 = a1 * l1 + a2 * v3
            let v2 = l2 + a2 * l1 + a3 * v3
            l1 = 2 * v1 - l1
            l2 = 2 * v2 - l2
            return v2
        }

        mutating func right(_ x: Double) -> Double {
            let v3 = x - r2
            let v1 = a1 * r1 + a2 * v3
            let v2 = r2 + a2 * r1 + a3 * v3
            r1 = 2 * v1 - r1
            r2 = 2 * v2 - r2
            return v2
        }
    }

    // MARK: - Constants (kept equal to BreathSynth.kt)

    private static let control = 32
    private static let outputGain = 1.3

    // Following the device clock.
    private static let snapSeconds = 0.25
    private static let catchUpSeconds = 2.0
    private static let maxNudge = 0.002
    private static let staleCue = 0.12
    private static let startFadeFromZero = 0.03
    private static let startFadeMidway = 0.8
    private static let fadeOutSeconds = 0.35

    // Pad. D2 D3 A3 hold the ground; F#4 A4 colour it. Each pitch is within 0.05 Hz of equal
    // temperament and a whole number of sixteenths of a hertz, as are the slight detunings,
    // so every beat between voices comes round exactly once a 16 s cycle.
    private static let notes: [Double] = [73.4375, 146.875, 220.0, 370.0, 440.0]
    private static let pedalCount = 3
    private static let baseGain: [Double] = [0.12, 0.085, 0.06, 0.045, 0.045]
    private static let detune: [Double] = [0.0625, 0.0625, 0.0625, 0.125, 0.125]
    private static let pedalHarmonic: [Double] = [0.0, 0.22, 0.16]
    private static let side = 0.28
    private static let padFadeIn = 4.5
    private static let padFadeOut = 6.5

    // Air.
    private static let airLevel = 0.5
    private static let airInhale = 1.0
    private static let airExhale = 0.9
    private static let airQ = 0.6
    fileprivate static let airHighpass = 90.0

    // Bells: four partials, the top one slightly stretched for a bell rather than an organ.
    private static let bellLevel = 0.16
    private static let maxBells = 10
    private static let partials = 4
    private static let partialRatio: [Double] = [1.0, 2.0, 3.0, 4.16]
    private static let partialAmp: [Double] = [1.0, 0.22, 0.06, 0.035]
    private static let partialDecay: [Double] = [2.4, 1.2, 0.6, 0.35]
    private static let bellAttack = 0.012
    private static let bellLife = 9.0
    private static let bellRelease = 1.0

    private static let welcomeAt = 0.3
    private static let cueWelcome = 4
    private static let cueClosing = 5

    // Per cue: (frequency, amplitude, delay seconds) triples. Indexed by phase 0...3, then
    // welcome and closing.
    private static let cueNotes: [[Double]] = [
        [440.0, 1.0, 0.0], // inhale: A4
        [659.255, 0.32, 0.0], // hold full: E5, quiet
        [293.665, 0.9, 0.0], // exhale: D4
        [220.0, 0.38, 0.0], // hold empty: A3, quiet
        [293.665, 0.55, 0.0, 440.0, 0.35, 0.16], // welcome
        [146.832, 0.5, 0.0, 293.665, 0.8, 0.0, 440.0, 0.6, 0.2, 739.989, 0.4, 0.4], // closing
    ]

    private static let tableSize = 4096
    private static let sineTable: UnsafeMutablePointer<Double> = {
        let p = UnsafeMutablePointer<Double>.allocate(capacity: tableSize + 1)
        for i in 0...tableSize { p[i] = sin(2 * Double.pi * Double(i) / Double(tableSize)) }
        return p
    }()

    private static func wrap(_ x: Double) -> Double { x >= 1 ? x - 1 : x }

    private static func raised(_ x: Double) -> Double { 0.5 - 0.5 * cos(Double.pi * min(max(x, 0), 1)) }

    /// Gentle limiter: untouched below 0.6, rounds off smoothly towards 1.0 above it.
    private static func soften(_ x: Double) -> Double {
        let a = abs(x)
        if a <= 0.6 { return x }
        let y = 0.6 + 0.4 * tanh((a - 0.6) / 0.4)
        return x < 0 ? -y : y
    }

    private static func xorshift(_ x0: UInt32) -> UInt32 {
        var x = x0
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        return x
    }

    private static func unit(_ x: UInt32) -> Double { Double(x >> 8) / 16777216.0 }

    /// White noise in -1...1, the same for the same `k` (a 32-bit integer hash).
    private static func noise(_ k: Int) -> Double {
        var x = UInt32(truncatingIfNeeded: k)
        x ^= x >> 16
        x &*= 0x7feb352d
        x ^= x >> 15
        x &*= 0x846ca68b
        x ^= x >> 16
        return Double(Int32(bitPattern: x)) / 2147483648.0
    }
}

import XCTest
@testable import BreatheCore

final class BreathSynthTests: XCTestCase {
    private let rate = 48_000.0

    /// Renders a whole session with exact timing, in blocks of `block` frames.
    private func render(_ plan: SessionPlan, mode: SoundMode = .ambient, block: Int = 480,
                        seconds: Double? = nil, solo: Int = -1, voice: [VoicePrompt?]? = nil,
                        configure: (BreathSynth) -> Void = { _ in }) -> (left: [Float], right: [Float]) {
        let synth = BreathSynth(sampleRate: rate, plan: plan, voice: voice)
        synth.mode = mode
        synth.volume = 1
        synth.solo = solo
        configure(synth)
        let total = Int((seconds ?? plan.endTime + SessionPlan.closingSeconds + 0.5) * rate)
        var left = [Float](repeating: 0, count: total)
        var right = [Float](repeating: 0, count: total)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                var n = 0
                while n < total {
                    let count = min(block, total - n)
                    synth.render(left: l.baseAddress! + n, right: r.baseAddress! + n, frames: count, startTime: Double(n) / rate)
                    n += count
                }
            }
        }
        return (left, right)
    }

    private func rms(_ x: [Float], _ from: Double, _ to: Double) -> Double {
        let a = Int(from * rate), b = Int(to * rate)
        var sum = 0.0
        for i in a..<b { sum += Double(x[i]) * Double(x[i]) }
        return (sum / Double(b - a)).squareRoot()
    }

    func testStaysCleanAndInsideFullScale() {
        let out = render(SessionPlan(cycles: 2))
        let peak = (out.left + out.right).map { abs(Double($0)) }.max()!
        XCTAssertTrue((out.left + out.right).allSatisfy { $0.isFinite })
        XCTAssertLessThan(peak, 0.7)
    }

    func testBlockSizeDoesNotChangeTheSound() {
        let plan = SessionPlan(cycles: 2)
        let a = render(plan, block: 256, seconds: 30)
        let b = render(plan, block: 997, seconds: 30)
        var worst = 0.0
        for i in a.left.indices { worst = max(worst, abs(Double(a.left[i] - b.left[i]))) }
        XCTAssertLessThan(worst, 1e-5)
    }

    func testBellsLandOnThePhaseBoundaries() {
        let plan = SessionPlan(cycles: 3)
        var cues: [(Int, Double, Double)] = []
        _ = render(plan, mode: .bells, block: 333) { $0.onCue = { cues.append(($0, $1, $2)) } }
        XCTAssertEqual(cues.count, plan.phaseCount + 2)
        // Each starts on the sample nearest its time, so on the same sample of every cycle.
        for (i, cue) in cues.enumerated() {
            let late = cue.2 - cue.1
            XCTAssertLessThanOrEqual(abs(late), 0.5 / rate + 1e-9, "cue \(i) off by \(late)")
        }
        for i in 0..<plan.phaseCount {
            XCTAssertEqual(cues[i + 1].0, i % 4)
            XCTAssertEqual(cues[i + 1].1, plan.phaseStart(i), accuracy: 1e-9)
        }
    }

    func testEveryCycleSoundsTheSame() {
        // After the first, every cycle is the same sound, sample for sample: the same chord,
        // the same slow shimmer, the same air and bells. (The first has no bell tails from a
        // cycle before it.)
        let plan = SessionPlan(cycles: 5)
        let cycle = Int(SessionPlan.cycleSeconds * rate)
        let second = Int((SessionPlan.settleSeconds + SessionPlan.cycleSeconds) * rate)
        for (solo, layer) in [(0, "pad"), (1, "air"), (2, "bells"), (-1, "all")] {
            let out = render(plan, seconds: SessionPlan.settleSeconds + 4 * SessionPlan.cycleSeconds, solo: solo)
            var worst = 0.0
            for i in 0..<cycle {
                worst = max(worst, abs(Double(out.left[second + i] - out.left[second + cycle + i])),
                            abs(Double(out.right[second + i] - out.right[second + cycle + i])))
            }
            print("\(layer): largest difference between cycles 2 and 3 \(worst)")
            XCTAssertLessThan(worst, 1e-5, "\(layer): cycles 2 and 3 differ")
        }
    }

    func testAirMovesOnlyWhileBreathMoves() {
        let air = render(SessionPlan(cycles: 2), solo: 1).left
        XCTAssertLessThan(rms(air, 12.5, 15.5), rms(air, 9, 11) * 0.01)
        XCTAssertLessThan(rms(air, 20.5, 23.5), rms(air, 17, 19) * 0.01)
    }

    func testFollowsAClockThatRunsSlightlyFast() {
        let plan = SessionPlan(cycles: 2)
        let synth = BreathSynth(sampleRate: rate, plan: plan)
        var cues: [(Double, Double)] = []
        synth.onCue = { _, scheduled, actual in cues.append((scheduled, actual)) }
        var l = [Float](repeating: 0, count: 480), r = l
        var n = 0
        while n < Int(rate) * 45 {
            synth.render(left: &l, right: &r, frames: 480, startTime: Double(n) / rate * (1 + 100e-6))
            n += 480
        }
        for (scheduled, actual) in cues { XCTAssertLessThan(abs(actual - scheduled), 0.002) }
    }

    func testFadeOutFinishes() {
        let synth = BreathSynth(sampleRate: rate, plan: SessionPlan(cycles: 2))
        var l = [Float](repeating: 0, count: 480), r = l
        var n = 0
        while n < Int(rate) * 12 { synth.render(left: &l, right: &r, frames: 480, startTime: Double(n) / rate); n += 480 }
        synth.fadeOut()
        var blocks = 0
        while !synth.finished && blocks < 1000 { synth.render(left: &l, right: &r, frames: 480, startTime: Double(n) / rate); n += 480; blocks += 1 }
        XCTAssertTrue(synth.finished)
        XCTAssertLessThan(blocks, 60)
    }

    // MARK: - Voice. Stand-in prompts: a steady tone each, of a different length per phase,
    // so each phase's prompt can be told apart and timed to the sample.

    private func tone(_ seconds: Double, lead: Double, level: Double = 0.2) -> VoicePrompt {
        let n = Int(seconds * rate)
        return VoicePrompt(samples: (0..<n).map { Float(level * cos(2 * Double.pi * 300 * Double($0) / rate)) }, lead: lead)
    }

    private lazy var hold = tone(0.25, lead: 0.10)
    private lazy var prompts: [VoicePrompt?] = [tone(0.40, lead: 0.15), hold, tone(0.35, lead: 0.05), hold]

    /// The runs of sound in `x`: (first sample, length), gaps under 5 ms joined.
    private func soundRuns(_ x: [Float]) -> [(start: Int, length: Int)] {
        var runs: [(start: Int, length: Int)] = []
        var start = -1
        var last = -1
        for i in x.indices where x[i] != 0 {
            if start < 0 || i - last > Int(rate) / 200 {
                if start >= 0 { runs.append((start, last - start + 1)) }
                start = i
            }
            last = i
        }
        if start >= 0 { runs.append((start, last - start + 1)) }
        return runs
    }

    func testEachPromptStartsItsLeadBeforeItsChange() {
        // Silent, so the voice is all there is: one run of sound per phase, starting on the
        // sample nearest (change - lead), as long as that phase's prompt.
        let plan = SessionPlan(cycles: 2)
        let runs = soundRuns(render(plan, mode: .silent, block: 333, voice: prompts).left)
        XCTAssertEqual(runs.count, plan.phaseCount)
        for (i, run) in runs.enumerated() {
            let p = prompts[i % 4]!
            let due = Int(((plan.phaseStart(i) - p.lead) * rate).rounded())
            XCTAssertLessThanOrEqual(abs(run.start - due), 1, "phase \(i)")
            XCTAssertEqual(run.length, p.samples.count, "phase \(i) plays its own prompt")
        }
    }

    func testAPromptIsNeverJoinedPartWay() {
        // Carrying on after a pause starts a new synth part way through the session. A prompt
        // already 0.1 s under way is let go; one only 20 ms under way still plays, from its start.
        let plan = SessionPlan(cycles: 2)
        let due = plan.phaseStart(1) - hold.lead
        func soundFrom(_ start: Double) -> [(start: Int, length: Int)] {
            let synth = BreathSynth(sampleRate: rate, plan: plan, voice: prompts)
            synth.mode = .silent
            let total = Int(rate) * 2
            var l = [Float](repeating: 0, count: total), r = l
            l.withUnsafeMutableBufferPointer { lp in
                r.withUnsafeMutableBufferPointer { rp in
                    var n = 0
                    while n < total {
                        synth.render(left: lp.baseAddress! + n, right: rp.baseAddress! + n, frames: 480,
                                     startTime: start + Double(n) / rate)
                        n += 480
                    }
                }
            }
            return soundRuns(l)
        }
        let late = soundFrom(due + 0.1)
        XCTAssertTrue(late.allSatisfy { Double($0.start) > 0.5 * rate }, "a prompt joined part way")
        // From its first sample to its last (the very first is silent: joining part way, the
        // sound fades in from nothing).
        let justLate = soundFrom(due + 0.02)
        XCTAssertLessThanOrEqual(justLate[0].start, 1)
        XCTAssertEqual(justLate[0].start + justLate[0].length, hold.samples.count)
    }

    func testUnderAVoiceTheRestPlaysFiveDecibelsQuieter() {
        // Before the first prompt (it is due at 7.85 s), compare the pad with and without.
        let plan = SessionPlan(cycles: 2)
        let plain = render(plan, seconds: 7.6)
        let voiced = render(plan, seconds: 7.6, voice: prompts)
        XCTAssertEqual(rms(voiced.left, 5.0, 7.5) / rms(plain.left, 5.0, 7.5), 0.562, accuracy: 0.003)
    }

    func testTheVoiceHasAVolumeOfItsOwn() {
        let plan = SessionPlan(cycles: 2)
        let full = render(plan, mode: .silent, seconds: 9, voice: prompts)
        let half = render(plan, mode: .silent, seconds: 9, voice: prompts) { $0.voiceVolume = 0.5 }
        // The slider is squared, as for everything else: half way is a quarter of the level.
        let peak = { (x: [Float]) in x.map { abs(Double($0)) }.max()! }
        XCTAssertEqual(peak(half.left) / peak(full.left), 0.25, accuracy: 0.01)
        // The tone's volume leaves the voice alone.
        let toneDown = render(plan, mode: .silent, seconds: 9, voice: prompts) { $0.volume = 0.5 }
        XCTAssertEqual(peak(toneDown.left) / peak(full.left), 1.0, accuracy: 1e-9)
    }

    func testTheVoiceVolumeLeavesTheToneAlone() {
        // Ambient into the first hold. Outside the prompts ("in" from 7.85 s for 0.40 s, "hold"
        // from 11.9 s) only the tone plays, and turning the voice down changes none of it.
        let plan = SessionPlan(cycles: 2)
        let full = render(plan, seconds: 12.5, voice: prompts)
        let quiet = render(plan, seconds: 12.5, voice: prompts) { $0.voiceVolume = 0.2 }
        let spoken: [(Double, Double)] = [(7.85, 8.25), (11.9, 12.15)]
        var differ = false
        for i in 0..<full.left.count {
            let t = Double(i) / rate
            if spoken.contains(where: { t >= $0.0 - 0.001 && t < $0.1 + 0.001 }) {
                differ = differ || full.left[i] != quiet.left[i]
                continue
            }
            XCTAssertEqual(full.left[i], quiet.left[i], "sample \(i)")
            XCTAssertEqual(full.right[i], quiet.right[i], "sample \(i)")
        }
        // While a prompt plays, the difference is the voice turned down.
        XCTAssertTrue(differ)
    }

    func testASessionWithItsVoiceStaysInsideFullScale() {
        // Prompts as loud as the real ones (peaks near 0.5 at -20 LUFS), faded in and out as
        // they are, over the full pad: nothing past full scale, nothing broken.
        func shaped(_ seconds: Double, lead: Double) -> VoicePrompt {
            let n = Int(seconds * rate)
            return VoicePrompt(samples: (0..<n).map {
                let t = Double($0) / rate
                let env = min(1, t / 0.01, (seconds - t) / 0.04)
                return Float(0.5 * env * sin(2 * Double.pi * 140 * t) * (0.6 + 0.4 * sin(2 * Double.pi * 7 * t)))
            }, lead: lead)
        }
        let h = shaped(0.85, lead: 0.167)
        let out = render(SessionPlan(cycles: 2), voice: [shaped(1.03, lead: 0.164), h, shaped(0.91, lead: 0.029), h])
        let all = out.left + out.right
        XCTAssertTrue(all.allSatisfy { $0.isFinite })
        XCTAssertLessThan(all.map { abs(Double($0)) }.max()!, 1.0)
    }

    func testBlockSizeDoesNotChangeTheVoice() {
        let plan = SessionPlan(cycles: 2)
        let a = render(plan, block: 256, seconds: 30, voice: prompts)
        let b = render(plan, block: 997, seconds: 30, voice: prompts)
        var worst = 0.0
        for i in a.left.indices { worst = max(worst, abs(Double(a.left[i] - b.left[i]))) }
        XCTAssertLessThan(worst, 1e-5)
    }

    /// Writes raw little-endian float32 stereo (interleaved) for comparison with the
    /// Android build, when BREATHE_RENDER_DIR is set.
    func testRenderForComparison() throws {
        guard let dir = ProcessInfo.processInfo.environment["BREATHE_RENDER_DIR"] else { return }
        let out = render(SessionPlan(cycles: 2))
        var data = Data(capacity: out.left.count * 8)
        for i in out.left.indices {
            var l = out.left[i].bitPattern.littleEndian, r = out.right[i].bitPattern.littleEndian
            withUnsafeBytes(of: &l) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &r) { data.append(contentsOf: $0) }
        }
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("swift-session.f32"))
    }
}

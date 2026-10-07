import XCTest
@testable import BreatheCore

final class BreathSynthTests: XCTestCase {
    private let rate = 48_000.0

    /// Renders a whole session with exact timing, in blocks of `block` frames.
    private func render(_ plan: SessionPlan, mode: SoundMode = .ambient, block: Int = 480,
                        seconds: Double? = nil, solo: Int = -1,
                        configure: (BreathSynth) -> Void = { _ in }) -> (left: [Float], right: [Float]) {
        let synth = BreathSynth(sampleRate: rate, plan: plan)
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

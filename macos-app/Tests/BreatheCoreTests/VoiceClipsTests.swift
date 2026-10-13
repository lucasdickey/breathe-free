import XCTest
@testable import BreatheCore

final class VoiceClipsTests: XCTestCase {
    private func sine(_ freq: Double, rate: Double, seconds: Double, level: Double = 0.5) -> [Float] {
        (0..<Int(seconds * rate)).map { Float(level * sin(2 * Double.pi * freq * Double($0) / rate)) }
    }

    private func rms(_ x: [Float], _ from: Int, _ to: Int) -> Double {
        var s = 0.0
        for i in from..<to { s += Double(x[i]) * Double(x[i]) }
        return (s / Double(to - from)).squareRoot()
    }

    func testAClipStartsAtItsFirstSound() {
        // A decoder's silence before and after (zeros, and noise far below the threshold) goes;
        // the sound itself stays, from its first sample at the threshold to its last.
        let sound: [Float] = [0.002, 0.3, -0.4, 0.1, -0.002]
        let padded = (0..<100).map { Float(0.0001) * Float($0 % 3 - 1) } + sound + [Float](repeating: 0, count: 50)
        XCTAssertEqual(VoiceClips.trimToSound(padded), sound)
        XCTAssertEqual(VoiceClips.trimToSound([Float](repeating: 0, count: 10)), [])
    }

    func testTheSameRateIsLeftAlone() {
        let x = sine(300, rate: 48_000, seconds: 0.1)
        XCTAssertEqual(VoiceClips.resample(x, from: 48_000, to: 48_000), x)
    }

    func testResamplingKeepsPitchLengthAndLevel() {
        // 48 kHz to 44.1 kHz: a 1 kHz tone stays 1 kHz and as loud, and the clip as long.
        let x = sine(1000, rate: 48_000, seconds: 0.5)
        let y = VoiceClips.resample(x, from: 48_000, to: 44_100)
        XCTAssertEqual(Double(y.count), Double(x.count) * 44_100 / 48_000, accuracy: 1)
        var crossings = 0
        for i in 1..<y.count where (y[i - 1] < 0) != (y[i] < 0) { crossings += 1 }
        XCTAssertEqual(Double(crossings) / 2 / (Double(y.count) / 44_100), 1000, accuracy: 5)
        XCTAssertEqual(rms(y, 2000, y.count - 2000) / rms(x, 2000, x.count - 2000), 1, accuracy: 0.01)
    }

    func testResamplingDownLeavesOutWhatTheNewRateCannotHold() {
        // 23 kHz fits at 48 kHz but not at 44.1 kHz (whose limit is 22.05 kHz): it must not fold
        // back as a lower, audible tone.
        let x = sine(23_000, rate: 48_000, seconds: 0.5)
        let y = VoiceClips.resample(x, from: 48_000, to: 44_100)
        XCTAssertLessThan(rms(y, 2000, y.count - 2000) / rms(x, 2000, x.count - 2000), 0.03)
    }

    func testPromptsComeInPhaseOrderWithOneHold() {
        let clips = VoiceClips(rate: 48_000,
                               breatheIn: sine(300, rate: 48_000, seconds: 1.0),
                               hold: sine(300, rate: 48_000, seconds: 0.8),
                               breatheOut: sine(300, rate: 48_000, seconds: 0.9))
        let p = clips.prompts(sampleRate: 48_000)
        XCTAssertEqual(p.count, 4)
        XCTAssertEqual(p[0]!.samples, clips.breatheIn)
        XCTAssertEqual(p[1]!.samples, clips.hold)
        XCTAssertEqual(p[2]!.samples, clips.breatheOut)
        XCTAssertEqual(p[3]!.samples, clips.hold)
        XCTAssertEqual(p[0]!.lead, VoiceClips.leadIn)
        XCTAssertEqual(p[1]!.lead, VoiceClips.leadHold)
        XCTAssertEqual(p[2]!.lead, VoiceClips.leadOut)
        XCTAssertEqual(p[3]!.lead, VoiceClips.leadHold)
        // At another rate they are resampled.
        let q = clips.prompts(sampleRate: 44_100)
        XCTAssertLessThanOrEqual(abs(clips.breatheIn.count * 44_100 / 48_000 - q[0]!.samples.count), 1)
    }
}

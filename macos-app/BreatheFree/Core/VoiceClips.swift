//
//  VoiceClips.swift
//  BreatheFree
//
//  The spoken prompts as decoded, made ready for the synth. A match of the Android app's
//  VoiceClips.kt.
//

import Foundation

/// The spoken prompts as decoded: mono samples at `rate`, each from its first sound to its
/// last (see `trimToSound`). The recordings and how they were made are in voice/README.md.
final class VoiceClips {
    let rate: Double
    let breatheIn: [Float]
    let hold: [Float]
    let breatheOut: [Float]

    private var cached: (rate: Double, prompts: [VoicePrompt?])?
    private let lock = NSLock()

    init(rate: Double, breatheIn: [Float], hold: [Float], breatheOut: [Float]) {
        self.rate = rate
        self.breatheIn = breatheIn
        self.hold = hold
        self.breatheOut = breatheOut
    }

    /// The prompts for a synth at `sampleRate`, in phase order: in, hold full, out, hold empty.
    func prompts(sampleRate: Double) -> [VoicePrompt?] {
        lock.lock()
        defer { lock.unlock() }
        if let c = cached, c.rate == sampleRate { return c.prompts }
        let held = VoicePrompt(samples: Self.resample(hold, from: rate, to: sampleRate), lead: Self.leadHold)
        let prompts: [VoicePrompt?] = [
            VoicePrompt(samples: Self.resample(breatheIn, from: rate, to: sampleRate), lead: Self.leadIn),
            held,
            VoicePrompt(samples: Self.resample(breatheOut, from: rate, to: sampleRate), lead: Self.leadOut),
            held,
        ]
        cached = (sampleRate, prompts)
        return prompts
    }

    // How long after each recording's first sound its main vowel comes, in seconds.
    static let leadIn = 0.164
    static let leadHold = 0.167
    static let leadOut = 0.029

    /// A sample at least this loud (-54 dBFS) is a clip's first or last sound. Anything outside
    /// it is silence a decoder added, which would put the prompt late.
    static let onset: Float = 0.002

    /// `samples` from the first sound to the last.
    static func trimToSound(_ samples: [Float]) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) >= onset }),
              let last = samples.lastIndex(where: { abs($0) >= onset }) else { return [] }
        return Array(samples[first...last])
    }

    /// `x` at `from` Hz, resampled to `to` Hz: a windowed sinc 16 zero crossings wide, its band
    /// edge at 0.9 of the new Nyquist when going down (the prompts hold nothing above about
    /// 16 kHz anyway). Only used when the output doesn't run at the recordings' 48 kHz.
    static func resample(_ x: [Float], from: Double, to: Double) -> [Float] {
        if from == to || x.isEmpty { return x }
        let step = from / to // source samples per output sample
        let cut = min(1.0, to / from) * 0.90
        let half = halfWidth / cut // kernel half-width, in source samples
        let n = Int((Double(x.count) / step).rounded(.down))
        var y = [Float](repeating: 0, count: n)
        for j in 0..<n {
            let t = Double(j) * step
            var sum = 0.0
            var norm = 0.0
            var k = Int((t - half).rounded(.up))
            let end = Int((t + half).rounded(.down))
            while k <= end {
                let d = t - Double(k)
                let w = cut * sinc(cut * d) * (0.5 + 0.5 * cos(Double.pi * d / half))
                norm += w
                if k >= 0 && k < x.count { sum += Double(x[k]) * w }
                k += 1
            }
            y[j] = Float(sum / norm)
        }
        return y
    }

    private static let halfWidth = 16.0

    private static func sinc(_ v: Double) -> Double {
        v == 0 ? 1 : sin(Double.pi * v) / (Double.pi * v)
    }
}

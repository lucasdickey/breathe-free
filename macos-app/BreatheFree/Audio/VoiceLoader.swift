//
//  VoiceLoader.swift
//  BreatheFree
//
//  Decodes the spoken prompts (AAC, in the app's resources) with AVAudioFile.
//

import AVFoundation

enum VoiceLoader {
    /// The three prompts, decoded once. Nil if anything goes wrong: sessions then play
    /// without a voice. Slow enough (a few milliseconds) to keep off the main thread.
    static func load() -> VoiceClips? {
        do {
            let breatheIn = try decode("breathe-in")
            let hold = try decode("hold")
            let breatheOut = try decode("breathe-out")
            guard hold.rate == breatheIn.rate, breatheOut.rate == breatheIn.rate else {
                NSLog("Breathe Free: the voice prompts are at different rates")
                return nil
            }
            return VoiceClips(rate: breatheIn.rate,
                              breatheIn: VoiceClips.trimToSound(breatheIn.samples),
                              hold: VoiceClips.trimToSound(hold.samples),
                              breatheOut: VoiceClips.trimToSound(breatheOut.samples))
        } catch {
            NSLog("Breathe Free: no voice prompts (\(error))")
            return nil
        }
    }

    private struct Missing: Error {
        let name: String
    }

    /// One resource decoded to mono samples, and their rate.
    private static func decode(_ name: String) throws -> (samples: [Float], rate: Double) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { throw Missing(name: name) }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw Missing(name: name)
        }
        try file.read(into: buffer)
        let frames = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        if let data = buffer.floatChannelData {
            // Mono: the average of the channels.
            for c in 0..<channels {
                for i in 0..<frames { mono[i] += data[c][i] / Float(channels) }
            }
        }
        return (mono, format.sampleRate)
    }
}

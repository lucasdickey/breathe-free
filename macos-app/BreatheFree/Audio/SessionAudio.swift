//
//  SessionAudio.swift
//  BreatheFree
//
//  Plays a session's sound in step with the session clock.
//

import AVFoundation
import QuartzCore

/// The screen keeps time with the host clock (CACurrentMediaTime): session time is
/// now - startTime. For every block it renders, Core Audio reports when that block reaches
/// the output, and the output device reports how much delay follows (presentationLatency,
/// which includes AirPods and other Bluetooth output). The synth is told the session time
/// at which each block will actually be heard and bends its own clock to match, so the
/// bell for "Breathe in" sounds as the words appear.
///
/// Because it lines itself up with a clock it doesn't own, it can also be started part way
/// through a session (sound switched back on) and still land on the beat.
final class SessionAudio {
    private let engine: AVAudioEngine
    private let synth: BreathSynth
    private let timing: Timing
    private var watch: Timer?
    private var configObserver: NSObjectProtocol?

    /// Instances fading out after stop(), kept alive until they fall silent.
    private static var fading: [ObjectIdentifier: SessionAudio] = [:]

    /// What the render thread reads. Written on the main thread only when the output changes.
    private final class Timing {
        let secondsPerHostTick: Double
        let startTime: Double
        var latency: Double

        init(startTime: Double, latency: Double) {
            var info = mach_timebase_info_data_t()
            mach_timebase_info(&info)
            secondsPerHostTick = Double(info.numer) / Double(info.denom) / 1e9
            self.startTime = startTime
            self.latency = latency
        }
    }

    /// Returns nil if there is no audio output to play on.
    init?(plan: SessionPlan, startTime: CFTimeInterval, mode: SoundMode, volume: Double) {
        let engine = AVAudioEngine()
        let output = engine.outputNode
        let hardwareRate = output.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return nil }

        let synth = BreathSynth(sampleRate: sampleRate, plan: plan)
        synth.mode = mode
        synth.volume = volume
        let timing = Timing(startTime: startTime, latency: output.presentationLatency)
        self.engine = engine
        self.synth = synth
        self.timing = timing
        let roughLead = 0.01

        let node = AVAudioSourceNode(format: format) { _, timestamp, frameCount, bufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard buffers.count >= 2,
                  let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let right = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let stamp = timestamp.pointee
            // When this block leaves for the device, on the same clock the screen uses.
            let outputTime = stamp.mFlags.contains(.hostTimeValid)
                ? Double(stamp.mHostTime) * timing.secondsPerHostTick
                : CACurrentMediaTime() + roughLead
            let heardAt = outputTime + timing.latency
            synth.render(left: left, right: right, frames: Int(frameCount), startTime: heardAt - timing.startTime)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            NSLog("Breathe Free: no audio output (\(error.localizedDescription))")
            return nil
        }

        // Headphones connected or a new output chosen: the engine stops. Pick up the new
        // device's delay and carry on; the synth re-aligns itself on the next block.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.timing.latency = self.engine.outputNode.presentationLatency
            try? self.engine.start()
        }
        // Let go of the output once the sound has finished (end of session or a fade-out).
        let watch = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, self.synth.finished else { return }
            self.shutDown()
        }
        RunLoop.main.add(watch, forMode: .common)
        self.watch = watch
    }

    deinit {
        watch?.invalidate()
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        engine.stop()
    }

    var mode: SoundMode {
        get { synth.mode }
        set { synth.mode = newValue }
    }

    var volume: Double {
        get { synth.volume }
        set { synth.volume = newValue }
    }

    /// Fade out over a third of a second, then release the output. Safe to drop the
    /// reference straight after: the instance keeps itself alive until it is silent.
    func stop() {
        Self.fading[ObjectIdentifier(self)] = self
        synth.fadeOut()
    }

    private func shutDown() {
        watch?.invalidate()
        watch = nil
        engine.stop()
        Self.fading[ObjectIdentifier(self)] = nil
    }
}

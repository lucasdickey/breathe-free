//
//  SessionModel.swift
//  BreatheFree
//
//  App state: the saved choices, the current screen, and the session's sound and touch.
//

import SwiftUI
import QuartzCore

enum Screen {
    case home, session, done
}

final class SessionModel: ObservableObject {
    @Published var cycles: Int {
        didSet { defaults.set(cycles, forKey: Keys.cycles) }
    }

    @Published var soundMode: SoundMode {
        didSet { defaults.set(soundMode.rawValue, forKey: Keys.sound) }
    }

    /// How loud the tone (pad, air and bells) is.
    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: Keys.volume)
            audio?.volume = volume
        }
    }

    /// How loud the voice is, apart from the tone. Before it has ever been set it starts as
    /// loud as the tone, the balance the voice was mixed at.
    @Published var voiceVolume: Double {
        didSet {
            defaults.set(voiceVolume, forKey: Keys.voiceVolume)
            audio?.voiceVolume = voiceVolume
        }
    }

    /// Say each change aloud ("Breathe in", "Hold", "Breathe out"). Off until chosen.
    @Published var voiceOn: Bool {
        didSet {
            defaults.set(voiceOn, forKey: Keys.voice)
            if voiceOn { prepareVoice() }
        }
    }

    @Published private(set) var screen: Screen = .home
    @Published private(set) var session: ActiveSession?

    private let defaults = UserDefaults.standard
    private var audio: SessionAudio?
    private var ticker: Timer?
    private var lastPhaseIndex = Int.min

    // The prompts, decoded once off the main thread: written before the group is left, read
    // only after waiting on it.
    private let voiceLoading = DispatchGroup()
    private var voiceRequested = false
    private var voiceClips: VoiceClips?

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: Keys.cycles)
        cycles = SessionPlan.cycleChoices.contains(saved) ? saved : SessionPlan.defaultCycles
        soundMode = SoundMode(rawValue: defaults.string(forKey: Keys.sound) ?? "") ?? .ambient
        let savedVolume = defaults.object(forKey: Keys.volume) as? Double ?? 0.85
        volume = savedVolume
        voiceVolume = defaults.object(forKey: Keys.voiceVolume) as? Double ?? savedVolume
        voiceOn = defaults.bool(forKey: Keys.voice)
        if voiceOn { prepareVoice() }
    }

    func begin() {
        stopAudio()
        // A short lead so the first frame and the first sample both land after "now".
        let active = ActiveSession(plan: SessionPlan(cycles: cycles), startTime: CACurrentMediaTime() + 0.35)
        session = active
        lastPhaseIndex = Int.min
        screen = .session
        startAudio(for: active, mode: soundMode)
        startTicker()
    }

    var isPaused: Bool { session?.isPaused ?? false }

    /// Hold the session still where it is: the picture stops and the sound fades out.
    func pause() {
        guard let active = session, !active.isPaused, screen == .session else { return }
        session = active.paused(at: CACurrentMediaTime())
        stopAudio()
    }

    /// Carry on from the moment it was paused; the sound fades back in on the beat.
    func resume() {
        guard let active = session, active.isPaused else { return }
        let resumed = active.resumed(at: CACurrentMediaTime())
        session = resumed
        startAudio(for: resumed, mode: soundMode)
    }

    /// The pause button and the space bar.
    func togglePause() {
        if isPaused { resume() } else { pause() }
    }

    /// Leave a session early (close button or Escape).
    func endSession() {
        stopAudio()
        stopTicker()
        session = nil
        screen = .home
    }

    /// From the completion screen. The closing chord is allowed to ring out.
    func backHome() {
        session = nil
        screen = .home
    }

    // MARK: - Private

    private func startAudio(for active: ActiveSession, mode: SoundMode) {
        let voice = voiceForSession()
        // Silent with the voice on still plays: the voice alone.
        guard mode != .silent || voice != nil else { return }
        audio = SessionAudio(plan: active.plan, startTime: active.startTime, mode: mode, volume: volume, voice: voice,
                             voiceVolume: voiceVolume)
    }

    /// Decodes the prompts once, off the main thread, so they're ready well before Begin.
    private func prepareVoice() {
        guard !voiceRequested else { return }
        voiceRequested = true
        voiceLoading.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.voiceClips = VoiceLoader.load()
            self.voiceLoading.leave()
        }
    }

    /// The prompts for a session starting now, or nil to play it without a voice.
    private func voiceForSession() -> VoiceClips? {
        guard voiceOn else { return nil }
        prepareVoice()
        // Decoding takes a few milliseconds and starts when the voice is chosen, so this only
        // waits if Begin comes straight after switching it on.
        guard voiceLoading.wait(timeout: .now() + 1.5) == .success else { return nil }
        return voiceClips
    }

    private func stopAudio() {
        audio?.stop()
        audio = nil
    }

    /// Watches the session clock for phase changes (for the trackpad) and the end. Runs
    /// apart from drawing so it keeps time even while the window is hidden.
    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard let active = session, screen == .session else {
            stopTicker()
            return
        }
        let frame = active.plan.frame(at: active.time(at: CACurrentMediaTime()))
        guard frame.phaseIndex != lastPhaseIndex else { return }
        let first = lastPhaseIndex == Int.min
        lastPhaseIndex = frame.phaseIndex
        if frame.stage == .complete {
            HapticManager.shared.complete()
            screen = .done
            stopTicker()
            return
        }
        if !first, let phase = frame.phase {
            HapticManager.shared.phaseChanged(to: phase)
        }
    }

    private enum Keys {
        static let cycles = "cycles"
        static let sound = "sound"
        static let volume = "volume"
        static let voice = "voice"
        static let voiceVolume = "voiceVolume"
    }
}

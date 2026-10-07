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

/// A session in progress: its plan and the host time (CACurrentMediaTime) at which its
/// time is zero.
struct ActiveSession: Equatable {
    let plan: SessionPlan
    let startTime: CFTimeInterval

    func time(at host: CFTimeInterval) -> Double { host - startTime }
}

final class SessionModel: ObservableObject {
    @Published var cycles: Int {
        didSet { defaults.set(cycles, forKey: Keys.cycles) }
    }

    @Published var soundMode: SoundMode {
        didSet { defaults.set(soundMode.rawValue, forKey: Keys.sound) }
    }

    @Published var volume: Double {
        didSet {
            defaults.set(volume, forKey: Keys.volume)
            audio?.volume = volume
        }
    }

    @Published private(set) var screen: Screen = .home
    @Published private(set) var session: ActiveSession?
    /// The sound for the session on screen; can change mid-session without changing the saved choice.
    @Published private(set) var sessionSound: SoundMode = .ambient

    private let defaults = UserDefaults.standard
    private var audio: SessionAudio?
    private var ticker: Timer?
    private var lastPhaseIndex = Int.min

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.integer(forKey: Keys.cycles)
        cycles = SessionPlan.cycleChoices.contains(saved) ? saved : SessionPlan.defaultCycles
        soundMode = SoundMode(rawValue: defaults.string(forKey: Keys.sound) ?? "") ?? .ambient
        volume = defaults.object(forKey: Keys.volume) as? Double ?? 0.85
    }

    func begin() {
        stopAudio()
        // A short lead so the first frame and the first sample both land after "now".
        let active = ActiveSession(plan: SessionPlan(cycles: cycles), startTime: CACurrentMediaTime() + 0.35)
        session = active
        sessionSound = soundMode
        lastPhaseIndex = Int.min
        screen = .session
        startAudio(for: active, mode: soundMode)
        startTicker()
    }

    /// The sound button during a session: ambient → bells only → silent → ambient.
    func nextSessionSound() {
        guard let active = session else { return }
        let next: SoundMode
        switch sessionSound {
        case .ambient: next = .bells
        case .bells: next = .silent
        case .silent: next = .ambient
        }
        sessionSound = next
        if next == .silent {
            stopAudio()
        } else if let audio {
            audio.mode = next
        } else {
            startAudio(for: active, mode: next)
        }
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
        guard mode != .silent else { return }
        audio = SessionAudio(plan: active.plan, startTime: active.startTime, mode: mode, volume: volume)
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
    }
}

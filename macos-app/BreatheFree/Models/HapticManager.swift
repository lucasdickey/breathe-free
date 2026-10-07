//
//  HapticManager.swift
//  BreatheFree
//
//  A tap on the Force Touch trackpad at each change of phase. macOS only plays these while
//  a finger is resting on the trackpad.
//

import AppKit

final class HapticManager {
    static let shared = HapticManager()

    private init() {}

    func phaseChanged(to phase: Phase) {
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch phase {
        case .inhale, .exhale:
            performer.perform(.alignment, performanceTime: .now)
        case .holdFull, .holdEmpty:
            performer.perform(.generic, performanceTime: .now)
        }
    }

    func complete() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

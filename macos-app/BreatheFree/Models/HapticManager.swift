//
//  HapticManager.swift
//  BreatheFree
//
//  Haptic feedback management for macOS trackpad
//

import Foundation
import AppKit

class HapticManager {
    static let shared = HapticManager()

    private init() {}

    func triggerHaptic(for state: BreathingState) {
        // macOS haptic feedback using NSHapticFeedbackManager
        let feedbackPerformer = NSHapticFeedbackManager.defaultPerformer

        switch state {
        case .preStart:
            // Success notification for settling period
            feedbackPerformer.perform(.levelChange, performanceTime: .now)

        case .breatheIn, .breatheOut:
            // Medium impact for breathing actions
            feedbackPerformer.perform(.alignment, performanceTime: .now)

        case .holdIn, .holdOut:
            // Light impact for holding
            feedbackPerformer.perform(.generic, performanceTime: .now)

        case .completed:
            // Success notification for completion
            feedbackPerformer.perform(.levelChange, performanceTime: .now)

        case .idle:
            // No haptic feedback for idle state
            break
        }
    }
}

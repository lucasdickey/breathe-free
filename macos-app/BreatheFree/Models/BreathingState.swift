//
//  BreathingState.swift
//  BreatheFree
//
//  Breathing state machine for box breathing pattern
//

import Foundation
import SwiftUI

enum BreathingState: String {
    case idle = "idle"
    case preStart = "pre-start"
    case breatheIn = "in"
    case holdIn = "hold-in"
    case breatheOut = "out"
    case holdOut = "hold-out"
    case completed = "completed"

    var displayText: String {
        switch self {
        case .idle:
            return "Ready"
        case .preStart:
            return "Settle your mind"
        case .breatheIn:
            return "Breathe in"
        case .holdIn:
            return "Hold"
        case .breatheOut:
            return "Breathe out"
        case .holdOut:
            return "Hold"
        case .completed:
            return "Be easy\nBreathe deeply"
        }
    }

    var balloonColor: Color {
        switch self {
        case .idle, .completed:
            return .white
        default:
            return Color(red: 0.024, green: 0.714, blue: 0.831) // Cyan
        }
    }

    var duration: Int {
        switch self {
        case .preStart:
            return 8 // 8 second settling period
        case .breatheIn, .holdIn, .breatheOut, .holdOut:
            return 4 // 4 seconds each for box breathing
        case .idle, .completed:
            return 0
        }
    }

    var nextState: BreathingState {
        switch self {
        case .idle:
            return .preStart
        case .preStart:
            return .breatheIn
        case .breatheIn:
            return .holdIn
        case .holdIn:
            return .breatheOut
        case .breatheOut:
            return .holdOut
        case .holdOut:
            return .breatheIn // Loop back for next cycle
        case .completed:
            return .idle
        }
    }

    var isActiveBreathing: Bool {
        switch self {
        case .breatheIn, .holdIn, .breatheOut, .holdOut:
            return true
        default:
            return false
        }
    }

    var shouldScaleBalloon: Bool {
        switch self {
        case .breatheIn, .holdIn:
            return true
        default:
            return false
        }
    }
}

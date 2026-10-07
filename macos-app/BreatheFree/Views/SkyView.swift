//
//  SkyView.swift
//  BreatheFree
//
//  The living sky behind every screen: day at home, dusk during a session (brightening
//  as the lungs fill), first light when finished.
//

import SwiftUI
import QuartzCore

struct SkyView: View {
    @ObservedObject var model: SessionModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var transition = PaletteTransition(.day)

    private var mood: SkyMood {
        switch model.screen {
        case .home: return .day
        case .session: return .dusk
        case .done: return .dawn
        }
    }

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let now = CACurrentMediaTime()
                transition.retarget(mood, at: now)
                let palette = transition.palette(at: now)
                var level = 0.0
                if model.screen == .session, let active = model.session {
                    level = active.plan.frame(at: active.time(at: now + SessionView.displayLead)).level
                }
                SceneDrawing.sky(&context, size: size, palette: palette, level: level)
                let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
                CloudField.shared.draw(in: &context, size: size, time: reduceMotion ? 0 : now,
                                       palette: palette, sprite: sprite)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A small orb that breathes slowly by itself, for the home and finish screens.
struct AmbientOrb: View {
    let colors: OrbColors
    var period = 10.0
    var depth = 1.0

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let t = CACurrentMediaTime()
                let level = depth * (0.5 - 0.5 * cos(2 * .pi * t / period))
                let side = Double(min(size.width, size.height))
                SceneDrawing.orb(&context, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                 radius: side * (0.2 + 0.1 * level), level: level, colors: colors)
            }
        }
        .accessibilityHidden(true)
    }
}

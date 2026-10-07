//
//  SkyView.swift
//  BreatheFree
//
//  The living sky behind every screen. It follows the time of day (DaySky), with stars at
//  night, and brightens a little during a session as the lungs fill.
//

import SwiftUI
import QuartzCore

/// The clock the views animate by. In the app it is the media clock; the promo renderer sets
/// `fixed` to draw any moment it chooses.
enum MediaClock {
    static var fixed: Double?

    static func now() -> Double { fixed ?? CACurrentMediaTime() }
}

struct SkyView: View {
    @ObservedObject var model: SessionModel
    let sky: SkyPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let now = MediaClock.now()
                var level = 0.0
                if model.screen == .session, let active = model.session {
                    level = active.plan.frame(at: active.time(at: now + SessionView.displayLead)).level
                }
                let t = reduceMotion ? 0 : now
                SceneDrawing.sky(&context, size: size, palette: sky, level: level)
                StarField.shared.draw(in: &context, size: size, time: t, amount: sky.stars)
                let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
                CloudField.shared.draw(in: &context, size: size, time: t, palette: sky, sprite: sprite)
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
                let t = MediaClock.now()
                let level = depth * (0.5 - 0.5 * cos(2 * .pi * t / period))
                let side = Double(min(size.width, size.height))
                SceneDrawing.orb(&context, center: CGPoint(x: size.width / 2, y: size.height / 2),
                                 radius: side * (0.2 + 0.1 * level), level: level, colors: colors)
            }
        }
        .accessibilityHidden(true)
    }
}

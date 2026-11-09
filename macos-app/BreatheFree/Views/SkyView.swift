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
    let sky: SkyPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { context, size in
                let t = reduceMotion ? 0 : MediaClock.now()
                SceneDrawing.sky(&context, size: size, palette: sky)
                StarField.shared.draw(in: &context, size: size, time: t, amount: sky.stars)
                let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
                CloudField.shared.draw(in: &context, size: size, time: t, palette: sky, sprite: sprite)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A small orb that breathes slowly by itself, for the home and finish screens. It can be pulled
/// about (OrbPoke, in Gestures.swift): it gives a little under the pointer, follows a drag a short
/// way, drawn out toward the pointer, and let go it springs home with a wobble and sends out a
/// ring. With Reduce Motion it follows, but goes home without the wobble or the ring.
struct AmbientOrb: View {
    let colors: OrbColors
    /// The side it is lit from (`Ink.sun`).
    let sun: Double
    var period = 10.0
    var depth = 1.0
    /// A pull to draw instead of the pointer's, for a renderer that shows a moment of one.
    var poked: OrbPoke?
    @Environment(\.ink) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var poke: OrbPoke?
    /// Whether the pointer is on it: back to false when the drag ends or is called off.
    @GestureState private var pressing = false

    /// How far round its frame it draws, as a multiple of its side: enough for the furthest pull,
    /// drawn out, and the ring at its widest.
    private static let room = 3.0

    var body: some View {
        GeometryReader { geo in
            let side = Double(min(geo.size.width, geo.size.height))
            ZStack {
                TimelineView(.animation) { _ in
                    Canvas { context, size in
                        draw(&context, size: size, side: side, at: MediaClock.now())
                    }
                }
                .frame(width: side * Self.room, height: side * Self.room)
                .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(pull(side: side))
            // Ended, or called off (as when the window loses the pointer): let go either way.
            .onChange(of: pressing) { held in
                if !held { letGo(side: side) }
            }
        }
        .accessibilityHidden(true)
    }

    private func level(_ t: Double) -> Double { depth * (0.5 - 0.5 * cos(2 * .pi * t / period)) }

    private func radius(side: Double, at t: Double) -> Double { side * (0.2 + 0.1 * level(t)) }

    private func draw(_ context: inout GraphicsContext, size: CGSize, side: Double, at t: Double) {
        let poke = self.poke ?? poked
        let home = CGPoint(x: size.width / 2, y: size.height / 2)
        if let ring = poke?.ring(at: t) {
            context.stroke(Path(ellipseIn: SceneDrawing.circle(home, ring.radius)),
                           with: .color(ink.line.color(ring.alpha)), lineWidth: 1.5)
        }
        let p = poke?.pull(at: t) ?? .zero
        let stretch = poke?.stretch(at: t) ?? 0
        let axis = poke?.axis ?? 0
        let r = radius(side: side, at: t) * (1 - OrbPoke.dent * (poke?.dent(at: t) ?? 0))
        // Drawn out along the way it was pulled, and narrower across it.
        var orb = context
        orb.translateBy(x: home.x + p.x, y: home.y + p.y)
        orb.rotate(by: .radians(axis))
        orb.scaleBy(x: 1 + stretch, y: 1 / (1 + stretch))
        orb.rotate(by: .radians(-axis))
        SceneDrawing.orb(&orb, center: .zero, radius: r, level: level(t), colors: colors, sun: sun)
    }

    private func pull(side: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($pressing) { _, pressing, _ in pressing = true }
            .onChanged { value in
                let t = MediaClock.now()
                print(String(format: "TRACE orb changed t=%.3f at=(%.0f,%.0f) held=\(poke?.isHeld ?? false)", t, value.location.x, value.location.y))
                if poke?.isHeld != true {
                    // Caught on its way home it carries on from where it is, unless the window
                    // has changed its size or Reduce Motion has been switched since.
                    var next = poke.flatMap { $0.side == side && $0.still == reduceMotion ? $0 : nil }
                        ?? OrbPoke(side: side, still: reduceMotion)
                    next.down(SIMD2(Double(value.startLocation.x), Double(value.startLocation.y)), at: t)
                    poke = next
                }
                poke?.move(SIMD2(Double(value.location.x), Double(value.location.y)), at: t)
            }
            .onEnded { _ in
                print(String(format: "TRACE orb ended t=%.3f held=\(poke?.isHeld ?? false)", MediaClock.now()))
                letGo(side: side)
            }
    }

    private func letGo(side: Double) {
        let t = MediaClock.now()
        poke?.up(at: t, radius: radius(side: side, at: t))
    }
}

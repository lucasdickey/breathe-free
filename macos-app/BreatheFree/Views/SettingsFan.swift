//
//  SettingsFan.swift
//  BreatheFree
//
//  Sound and voice, folded into one round button at the top right of the home screen, where a
//  session's ✕ sits. Clicked, its sliders turn into a ✕ and the settings open out of it as a fan
//  of drops of the same liquid as the session-length circle (LiquidFan): out of the button as
//  one drop, then swinging round it, down and to the left, the second pulling free of the
//  first, each showing its setting's icon. A click on a drop changes that setting and leaves
//  the fan open, so both can be changed; the ✕, a click anywhere else, Escape or Command-comma
//  folds it. A drop wears the lit colour while its setting is on. With Reduce Motion on, the
//  drops fade in and out in place. Kept in step with the browser version's settings-fan.tsx and
//  the Android app's SettingsFan.kt.
//

import SwiftUI

struct SettingsFan: View {
    @Binding var open: Bool
    @Binding var sound: SoundMode
    @Binding var voice: Bool
    @Environment(\.ink) private var ink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The fan's motion since it last opened or folded, or a setting last changed.
    @State private var motion: FanMotion?
    @State private var hovering = false

    /// The drops, the size of the session-length circle's.
    private static let size = 46.0
    /// The round button, the size of a session's.
    private static let button = 40.0
    /// From the button's centre to each drop's.
    private static let distance = 90.0
    /// The fan reaches this far left of and below the button's centre...
    private static let far = (distance * 1.12 + size * 0.75 + 16).rounded(.up)
    /// ...and to the window's edges right of and above it, the button sitting where a session's
    /// ✕ does: 16 points in from the right and 14 down.
    private static let right = 16 + button / 2
    private static let top = 14 + button / 2

    var body: some View {
        let lit = [sound != .silent, voice]
        TimelineView(.animation) { _ in
            let now = MediaClock.now()
            let motion = drawnMotion(lit: lit, at: now)
            let fan = motion.shape(at: now, size: Self.size, button: Self.button, distance: Self.distance)
            let shown = motion.shown(at: now)
            ZStack {
                Canvas { context, _ in
                    context.translateBy(x: Self.far, y: Self.top)
                    draw(&context, fan: fan, plain: motion.reduced || motion.isSettled(at: now), shown: shown)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                soundDrop(fan.drops[0], shown: shown, lit: motion.lit(0, at: now))
                    .position(x: Self.far + fan.drops[0].x, y: Self.top + fan.drops[0].y)
                voiceDrop(fan.drops[1], shown: shown, lit: motion.lit(1, at: now))
                    .position(x: Self.far + fan.drops[1].x, y: Self.top + fan.drops[1].y)
                // The button itself, over the drops waiting inside it.
                mainButton
                    .position(x: Self.far, y: Self.top)
            }
        }
        .frame(width: Self.far + Self.right, height: Self.far + Self.top)
        .onChange(of: open) { isOpen in
            let before = motion ?? FanMotion(open: !isOpen, lit: lit)
            if before.opening != isOpen {
                motion = before.changed(open: isOpen, reduced: reduceMotion, at: MediaClock.now())
            }
        }
        .onChange(of: lit) { newLit in
            motion = drawnMotion(lit: newLit, at: MediaClock.now())
        }
    }

    /// The motion to draw: the fan's own since it last changed, else the fan at rest, carried on
    /// from any change made a moment ago and not yet recorded.
    private func drawnMotion(lit: [Bool], at now: Double) -> FanMotion {
        var current = motion ?? FanMotion(open: open, lit: lit)
        if current.opening != open {
            current = current.changed(open: open, reduced: reduceMotion, at: now)
        }
        if current.on != lit {
            current = current.relit(lit, at: now)
        }
        return current
    }

    private var mainButton: some View {
        Button {
            open.toggle()
        } label: {
            SlidersGlyph(crossed: open)
                .frame(width: Self.button, height: Self.button)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut(",")
        .accessibilityLabel("Sound and voice")
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        .help("Sound and voice")
    }

    private func soundDrop(_ drop: FanDrop, shown: Double, lit: Double) -> some View {
        let next = Self.after(sound)
        return dropButton(drop, shown: shown, lit: lit, icon: FanIcons.sound(sound)) { sound = next }
            .accessibilityLabel("Sound")
            .accessibilityValue(Self.name(sound))
            .accessibilityHint("Click for \(Self.name(next)).")
            .help("Sound: \(Self.name(sound)). Click for \(Self.name(next)).")
    }

    private func voiceDrop(_ drop: FanDrop, shown: Double, lit: Double) -> some View {
        dropButton(drop, shown: shown, lit: lit, icon: voice ? FanIcons.voiceOn : FanIcons.voiceOff) { voice.toggle() }
            .accessibilityLabel("Voice guidance")
            .accessibilityValue(voice ? "On" : "Off")
            .help("Voice guidance")
    }

    /// A setting's drop: a real button over its circle in the liquid, moved with it, its icon as
    /// clear as the drop is. Folded, it waits inside the fan's button, where it can't be clicked
    /// or found.
    private func dropButton(_ drop: FanDrop, shown: Double, lit: Double, icon: [PathPiece],
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconShape(pieces: icon)
                .stroke(style: StrokeStyle(lineWidth: 2 * 22 / 24, lineCap: .round, lineJoin: .round))
                .foregroundColor(ink.deep.mix(ink.onAccent, lit).color)
                .frame(width: 22, height: 22)
                .opacity(drop.label * shown)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityHidden(!open)
    }

    /// The button and the drops: plain circles at rest or fading in place, and on the move all
    /// of them as one shape of liquid, run together wherever they meet; with a rim inside the
    /// edge, and the drops whose setting is on solid on top.
    private func draw(_ context: inout GraphicsContext, fan: FanShape, plain: Bool, shown: Double) {
        let fill = ink.field.color, edge = ink.fieldBorder.color
        if plain {
            context.fill(circle(fan.home, inset: 0), with: .color(hovering ? ink.glassPressed.color : fill))
            context.stroke(circle(fan.home, inset: 0.5), with: .color(edge), lineWidth: 1)
            var drops = context
            drops.opacity = shown
            for d in fan.drops where d.radius > 0.05 {
                drops.fill(circle(d.liquid, inset: 0), with: .color(fill))
                drops.stroke(circle(d.liquid, inset: 0.5), with: .color(edge), lineWidth: 1)
            }
        } else {
            var outline = Path()
            for loop in LiquidOutline.loops([fan.home] + fan.drops.map(\.liquid), inset: 0.5, cell: 2) {
                outline.move(to: CGPoint(x: loop[0].x, y: loop[0].y))
                for p in loop.dropFirst() {
                    outline.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                outline.closeSubpath()
            }
            context.fill(outline, with: .color(fill), style: FillStyle(eoFill: true))
            context.stroke(outline, with: .color(edge), lineWidth: 1)
        }
        for d in fan.drops where d.accent > 0 && d.radius > 0.05 {
            // Drawn out along the way it is going.
            var lit = context
            lit.opacity = shown
            lit.translateBy(x: d.x, y: d.y)
            lit.rotate(by: .radians(d.angle))
            let rect = CGRect(x: -d.radius * d.stretch, y: -d.radius / d.stretch,
                              width: 2 * d.radius * d.stretch, height: 2 * d.radius / d.stretch)
            lit.fill(Path(ellipseIn: rect), with: .color(ink.accent.color(min(1, d.accent))))
        }
    }

    private func circle(_ d: LiquidDrop, inset: Double) -> Path {
        let r = max(0, d.radius - inset)
        return Path(ellipseIn: CGRect(x: d.x - r, y: d.y - r, width: 2 * r, height: 2 * r))
    }

    /// The sound after `mode`, round Ambient, Bells and Silent.
    private static func after(_ mode: SoundMode) -> SoundMode {
        let all = SoundMode.allCases
        return all[((all.firstIndex(of: mode) ?? 0) + 1) % all.count]
    }

    private static func name(_ mode: SoundMode) -> String {
        switch mode {
        case .ambient: return "Ambient"
        case .bells: return "Bells"
        case .silent: return "Silent"
        }
    }
}

/// An icon from path pieces on a 24-unit grid (FanIcons), scaled to where it is drawn.
private struct IconShape: Shape {
    let pieces: [PathPiece]

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width, rect.height) / 24
        func point(_ v: SIMD2<Double>) -> CGPoint { CGPoint(x: rect.minX + v.x * k, y: rect.minY + v.y * k) }
        var path = Path()
        for piece in pieces {
            switch piece {
            case .move(let p): path.move(to: point(p))
            case .line(let p): path.addLine(to: point(p))
            case .curve(let c1, let c2, let p): path.addCurve(to: point(p), control1: point(c1), control2: point(c2))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}

/// The button's icon: two sliders, each a bar with its knob, that meet in the middle and cross
/// into a ✕ when the fan opens, their knobs shrinking away.
private struct SlidersGlyph: View {
    let crossed: Bool
    @Environment(\.ink) private var ink

    var body: some View {
        ZStack {
            bar(side: -1, knob: 15)
            bar(side: 1, knob: 9)
        }
        .frame(width: 18, height: 18)
        .foregroundColor(ink.deep.color)
    }

    /// One slider on the icons' 24-unit grid, drawn 18 points across: a bar from 4 to 20, 4.5
    /// above (`side` -1) or below (1) the middle, with its knob at `knob`.
    private func bar(side: Double, knob: Double) -> some View {
        let k = 18.0 / 24
        return ZStack {
            Capsule().frame(width: 18 * k, height: 2 * k)
            Circle()
                .frame(width: 5.2 * k, height: 5.2 * k)
                .scaleEffect(crossed ? 0.001 : 1)
                .animation(.timingCurve(0.25, 0.1, 0.25, 1, duration: 0.2), value: crossed)
                .offset(x: (knob - 12) * k)
        }
        .scaleEffect(x: crossed ? 1.06 : 1, y: 1)
        .rotationEffect(.degrees(crossed ? -side * 45 : 0))
        .offset(y: crossed ? 0 : side * 4.5 * k)
        .animation(.timingCurve(0.34, 1.45, 0.5, 1, duration: 0.32), value: crossed)
    }
}

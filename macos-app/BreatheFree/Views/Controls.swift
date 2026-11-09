//
//  Controls.swift
//  BreatheFree
//
//  Buttons and the session-length picker, styled to sit on the sky in the colours the sky calls
//  for (Ink).
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Styled(configuration: configuration)
    }

    struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.ink) private var ink

        var body: some View {
            configuration.label
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(ink.onAccent.color)
                .frame(maxWidth: 360)
                .frame(height: 50)
                .background(Capsule().fill((configuration.isPressed ? ink.accentPressed : ink.accent).color))
                .contentShape(Capsule())
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
        }
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        Styled(configuration: configuration)
    }

    struct Styled: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.ink) private var ink

        var body: some View {
            configuration.label
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(ink.deep.color)
                .frame(maxWidth: 360)
                .frame(height: 46)
                .background(Capsule().fill(ink.deep.color(configuration.isPressed ? 0.16 : 0.05)))
                .overlay(Capsule().stroke(ink.deep.color(0.55), lineWidth: 1))
                .contentShape(Capsule())
        }
    }
}

/// When the session-length picker last opened or closed, on the media clock, and the count
/// chosen before, for a renderer that draws moments of the motion itself (the promo). The app
/// leaves it unset, and the picker keeps its own time.
struct PickerMoment: Equatable {
    var changedAt: Double
    var previous: Int
}

private struct PickerMomentKey: EnvironmentKey {
    static let defaultValue: PickerMoment? = nil
}

extension EnvironmentValues {
    var pickerMoment: PickerMoment? {
        get { self[PickerMomentKey.self] }
        set { self[PickerMomentKey.self] = newValue }
    }
}

/// Session length as one drop showing the current count. Clicking it opens the row: the other
/// counts bud out of it as liquid and pull free to its left and right, nearest first; clicking
/// one picks it, and they all flow back into it (LiquidPicker.swift). The home screen folds the
/// row too on a click anywhere else, and on Escape.
///
/// Open, it can be slid too: pressed and dragged sideways, the chosen colour comes away under the
/// pointer as a bead of the same liquid, running into each drop it passes, with a tick on the
/// trackpad at each. Let go, it carries on to the drop it was heading for, and that one is picked.
/// Past the first or last drop it holds back (BeadSlide, in Gestures.swift). Folded, it only
/// opens: the row opens round its middle, not round the drop that was pressed, so a slide from
/// there would land somewhere the pointer never chose.
struct CyclePicker: View {
    let choices: [Int]
    @Binding var selection: Int
    @Binding var open: Bool
    let describe: (Int) -> String
    /// A slide to draw instead of the pointer's, for the screen renderer.
    var slid: BeadSlide?
    @Environment(\.ink) private var ink
    @Environment(\.pickerMoment) private var moment
    /// The drops' motion since the picker last opened or closed.
    @State private var motion: PickerMotion?
    /// The bead, while it is out: under the pointer, or on its way to a drop once let go.
    @State private var slide: BeadSlide?
    /// Whether a slide is under way: back to false when it ends or is called off.
    @GestureState private var sliding = false

    private let size: CGFloat = 46
    private let gap: CGFloat = 8

    var body: some View {
        let chosen = choices.firstIndex(of: selection) ?? 0
        let width = CGFloat(choices.count) * size + CGFloat(choices.count - 1) * gap
        TimelineView(.animation) { _ in
            let now = MediaClock.now()
            let motion = drawnMotion(chosen: chosen, at: now)
            let drops = motion.drops(at: now, size: size, step: size + gap)
            let slide = self.slide ?? slid
            let bead = slide.map {
                PickerDrop(x: $0.bead(at: now), radius: size / 2, stretch: $0.beadStretch(at: now),
                           reach: BeadSlide.reach * size, accent: 1, label: 0)
            }
            ZStack {
                ForEach(choices.indices, id: \.self) { i in
                    count(i, drop: drops[i], chosen: chosen, under: slide?.under(drops[i].x, at: now))
                }
            }
            .frame(width: width, height: size)
            .background {
                Canvas { context, canvas in
                    context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    drawLiquid(&context, drops: drops, order: motion.order,
                               settled: bead == nil && motion.isSettled(at: now), bead: bead)
                }
                .frame(width: width + 2 * size, height: 2 * size)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // Between the drops too, a press starts from the nearest.
            .contentShape(Rectangle())
        }
        .simultaneousGesture(slideGesture(width: Double(width)), including: open ? .all : .subviews)
        // Ended, or called off: the bead is let go either way.
        .onChange(of: sliding) { on in
            if !on, slide?.isSliding == true { slide?.up(at: MediaClock.now()) }
        }
        .onChange(of: open) { isOpen in
            // Folded from outside, by a click elsewhere or Escape: the drops go from where they are.
            let now = MediaClock.now()
            let before = motion ?? PickerMotion(count: choices.count, open: !isOpen, chosen: chosen)
            if before.opening != isOpen {
                motion = before.changed(open: isOpen, chosen: chosen, at: now)
            }
            if !isOpen { slide = nil }
        }
        // Let go, the bead carries on to its drop, and that one is picked when it arrives.
        .task(id: slide?.letGoAt ?? -.infinity) {
            guard let sent = slide, let target = sent.target, let arrives = sent.arrivesAt else { return }
            let wait = arrives - MediaClock.now()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            guard !Task.isCancelled, slide?.letGoAt == sent.letGoAt else { return }
            if target != sent.over { HapticManager.shared.tick() }
            pick(target, chosen: chosen)
        }
    }

    private func slideGesture(width: Double) -> some Gesture {
        // Far enough to mean it, it is a slide rather than a click on a drop.
        DragGesture(minimumDistance: 4)
            .updating($sliding) { _, sliding, _ in sliding = true }
            .onChanged { value in
                let t = MediaClock.now()
                if slide?.isSliding != true {
                    slide = BeadSlide(count: choices.count, step: Double(size + gap), size: Double(size),
                                      pointer: Double(value.startLocation.x) - width / 2)
                }
                if slide?.move(Double(value.location.x) - width / 2, at: t) == true {
                    HapticManager.shared.tick()
                }
            }
            .onEnded { _ in
                slide?.up(at: MediaClock.now())
            }
    }

    /// The motion to draw: the promo's moment if it set one, else the picker's own since it last
    /// opened or closed, else the drops at rest.
    private func drawnMotion(chosen: Int, at now: Double) -> PickerMotion {
        if let moment {
            return PickerMotion(count: choices.count, open: !open, chosen: open ? chosen : moment.previous)
                .changed(open: open, chosen: chosen, at: moment.changedAt)
        }
        guard let motion else { return PickerMotion(count: choices.count, open: open, chosen: chosen) }
        if motion.opening != open {
            // Opened or folded from outside a moment ago, before the change is recorded.
            return motion.changed(open: open, chosen: chosen, at: now)
        }
        return motion.chosen == chosen ? motion : PickerMotion(count: choices.count, open: open, chosen: chosen)
    }

    /// Drop `i`'s count. Half under the bead, a count fades out, and comes back light on it or
    /// dark off it.
    private func count(_ i: Int, drop: PickerDrop, chosen: Int, under: Double?) -> some View {
        let n = choices[i]
        let current = i == chosen
        let shown = open || current
        let on = under.map { $0 < 0.5 ? 0 : 1 } ?? drop.accent
        return Button {
            press(i, chosen: chosen)
        } label: {
            Text("\(n)")
                .font(.system(size: 16, weight: current ? .semibold : .regular))
                .foregroundColor(ink.deep.mix(ink.onAccent, on).color)
                .opacity(drop.label * (under.map { abs(2 * $0 - 1) } ?? 1))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .offset(x: drop.x)
        // Where the drops overlap, the chosen count takes the click.
        .zIndex(current ? 1 : 0)
        .allowsHitTesting(shown)
        .accessibilityHidden(!shown)
        .accessibilityLabel(open ? describe(n) : "Session length: \(describe(n)). Click to change.")
        .accessibilityAddTraits(open && current ? .isSelected : [])
    }

    private func press(_ i: Int, chosen: Int) {
        // A slide that ends where it began is not a click on that drop: the bead decides.
        guard slide == nil else { return }
        let now = MediaClock.now()
        let before = drawnMotion(chosen: chosen, at: now)
        if open {
            motion = before.changed(open: false, chosen: i, at: now)
            selection = choices[i]
            open = false
        } else {
            motion = before.changed(open: true, chosen: chosen, at: now)
            open = true
        }
    }

    /// The bead has arrived at drop `i`: it becomes the chosen drop there, and the row folds into it.
    private func pick(_ i: Int, chosen: Int) {
        let now = MediaClock.now()
        var next = drawnMotion(chosen: chosen, at: now).changed(open: false, chosen: i, at: now)
        // It already wears the chosen colour, as the bead did; the drop it left does not.
        next.previous = i
        motion = next
        slide = nil
        selection = choices[i]
        open = false
    }

    /// All the drops as one shape of liquid in the unchosen colours, run together wherever they
    /// meet, with a rim inside its edge, and the chosen one solid on top. While the chosen colour
    /// is out as a `bead`, it is part of the liquid too, solid on top in its place.
    private func drawLiquid(_ context: inout GraphicsContext, drops: [PickerDrop], order: [Int], settled: Bool,
                            bead: PickerDrop?) {
        if settled {
            // At rest the drops are plain circles, with no need to trace them.
            var fill = Path(), rim = Path()
            for d in drops where d.radius > 0.05 {
                fill.addEllipse(in: CGRect(x: d.x - d.radius, y: -d.radius, width: 2 * d.radius, height: 2 * d.radius))
                let r = d.radius - 0.5
                rim.addEllipse(in: CGRect(x: d.x - r, y: -r, width: 2 * r, height: 2 * r))
            }
            context.fill(fill, with: .color(ink.field.color))
            context.stroke(rim, with: .color(ink.fieldBorder.color), lineWidth: 1)
        } else {
            var outline = Path()
            let liquid = order.map { drops[$0].liquid } + (bead.map { [$0.liquid] } ?? [])
            for loop in LiquidOutline.loops(liquid, inset: 0.5) {
                outline.move(to: CGPoint(x: loop[0].x, y: loop[0].y))
                for p in loop.dropFirst() {
                    outline.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                outline.closeSubpath()
            }
            context.fill(outline, with: .color(ink.field.color), style: FillStyle(eoFill: true))
            context.stroke(outline, with: .color(ink.fieldBorder.color), lineWidth: 1)
        }
        for d in bead.map({ [$0] }) ?? drops where d.accent > 0 && d.radius > 0.05 {
            let rect = CGRect(x: d.x - d.radius * d.stretch, y: -d.radius / d.stretch,
                              width: 2 * d.radius * d.stretch, height: 2 * d.radius / d.stretch)
            context.fill(Path(ellipseIn: rect), with: .color(ink.accent.color(d.accent)))
        }
    }
}

/// A round, see-through button for the session's top bar.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void
    @Environment(\.ink) private var ink

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(ink.deep.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(ink.glass.color))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}

/// The ✕ that ends a session, so a stray click can't. Held for a second, it ends it: pressed, it
/// opens into "Hold to end" and fills from the left at an even pace, as time passing does; let go
/// too soon, the fill drains away quickly (HoldFill, in Gestures.swift). A click only opens it.
/// Escape, and VoiceOver, which can't hold, take two presses instead: the first opens it into
/// "End session", and the second ends it. Without `hold`, a click does the same. Left alone it
/// closes again, and a second press too quick to be meant (a double click) does nothing.
struct EndSessionButton: View {
    let end: () -> Void
    /// Whether it ends a session when held, rather than on a second click.
    var hold = true
    /// Told when it opens and when it closes again.
    var opened: (Bool) -> Void = { _ in }
    @State private var open: Bool
    @State private var label: String
    @State private var ready = false
    @State private var fill = HoldFill()
    /// Slid off while held: it lets go, and waits for the next press.
    @State private var slidOff = false
    /// Whether the pointer is on it: back to false when the press ends or is called off.
    @GestureState private var touching = false
    @State private var size = CGSize.zero
    /// A fill to draw, for the screen renderer.
    private let filled: Double?
    @Environment(\.ink) private var ink

    /// How long it stays open for the second press, and how soon it starts to listen.
    private static let openFor = Duration.seconds(4)
    private static let readyAfter = Duration.milliseconds(300)
    /// Opening and closing move the buttons beside it too, so the whole bar eases together.
    private static let opening = Animation.easeOut(duration: 0.2)

    /// `filled` starts it open, held and that full, as the screen renderer shows it.
    init(open: Bool = false, filled: Double? = nil, hold: Bool = true, end: @escaping () -> Void,
         opened: @escaping (Bool) -> Void = { _ in }) {
        _open = State(initialValue: open || filled != nil)
        _label = State(initialValue: filled != nil ? "Hold to end" : "End session")
        self.filled = filled
        self.hold = hold
        self.end = end
        self.opened = opened
    }

    var body: some View {
        TimelineView(.animation) { _ in
            let f = filled ?? fill.fill(at: MediaClock.now())
            HStack(spacing: 6) {
                if open {
                    Text(label).font(.system(size: 13, weight: .semibold))
                }
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(ink.deep.color)
            .padding(.horizontal, open ? 14 : 0)
            .frame(minWidth: 40, minHeight: 40, maxHeight: 40)
            .background(alignment: .leading) {
                Rectangle().fill(ink.deep.color(0.2)).frame(width: size.width * f)
            }
            .background(Capsule().fill((fill.isHeld || filled != nil ? ink.glassPressed : ink.glass).color))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { size = g.size }
                    .onChange(of: g.size) { size = $0 }
            }
        }
        .gesture(holding, including: hold ? .all : .subviews)
        // Ended, or called off: it lets go either way, so a press that is lost never ends a session.
        .onChange(of: touching) { on in
            if !on {
                fill.release(at: MediaClock.now())
                slidOff = false
            }
        }
        .gesture(TapGesture().onEnded { ask() }, including: hold ? .subviews : .all)
        // Escape: the same two presses as VoiceOver.
        .background {
            Button("End session", action: ask)
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("End session")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { ask() }
        .accessibilityHint(open ? "Press again to end the session." : "Asks before it ends the session.")
        .help(hold ? "Hold to end the session" : open ? "Click again to end the session" : "End session")
        .onChange(of: open) { opened($0) }
        // Open and not held, it closes again by itself.
        .task(id: open ? (fill.isHeld ? 2 : 1) : 0) {
            ready = false
            guard open, !fill.isHeld else { return }
            do {
                try await Task.sleep(for: Self.readyAfter)
                ready = true
                try await Task.sleep(for: Self.openFor - Self.readyAfter)
                withAnimation(Self.opening) { open = false }
            } catch {}
        }
        // Held until full, it ends the session.
        .task(id: fill.fullAt ?? -.infinity) {
            guard let fullAt = fill.fullAt else { return }
            let wait = fullAt - MediaClock.now()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
            guard !Task.isCancelled, fill.isHeld else { return }
            HapticManager.shared.tick()
            end()
        }
    }

    private var holding: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { value in
                let t = MediaClock.now()
                let on = CGRect(origin: .zero, size: size).insetBy(dx: -6, dy: -6).contains(value.location)
                if !fill.isHeld && !slidOff && on {
                    fill.press(at: t)
                    label = "Hold to end"
                    if !open { withAnimation(Self.opening) { open = true } }
                } else if fill.isHeld && !on {
                    fill.release(at: t)
                    slidOff = true
                }
            }
            .onEnded { _ in
                fill.release(at: MediaClock.now())
                slidOff = false
            }
    }

    /// A click without `hold`, Escape or VoiceOver: open it, or end the session if it is open.
    private func ask() {
        if !open {
            label = "End session"
            withAnimation(Self.opening) { open = true }
        } else if ready {
            end()
        }
    }
}

/// A slider from 0 to 1, for the volume: drag along it or click where you want it. Dragged on
/// past an end, it gives: the bar stretches the way it is pulled, less the further it goes, and
/// springs back when let go (Give, in Gestures.swift), with a tick on the trackpad as it reaches
/// an end. VoiceOver sets it as it does any slider.
struct GiveSlider: View {
    @Binding var value: Double
    let label: String
    /// A stretch to draw, for the screen renderer.
    var stretched: Double?
    @State private var give = Give()
    @State private var dragging = false
    @State private var atEnd = false
    /// Whether the pointer is on it: back to false when the drag ends or is called off.
    @GestureState private var touching = false

    private static let thumb = 9.0
    private static let track = 4.0

    var body: some View {
        GeometryReader { g in
            ZStack {
                // Drawn a little wider than its place, so the knob isn't cut off as it stretches.
                TimelineView(.animation) { _ in
                    Canvas { context, size in
                        draw(&context, width: Double(g.size.width), height: Double(size.height),
                             stretch: stretched ?? give.stretch(at: MediaClock.now()))
                    }
                }
                .frame(width: g.size.width + 2 * Give.limit, height: g.size.height)
                .allowsHitTesting(false)
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(drag(width: Double(g.size.width)))
            .onChange(of: touching) { on in
                if !on {
                    dragging = false
                    give.release(at: MediaClock.now())
                }
            }
        }
        .frame(height: 22)
        .accessibilityRepresentation {
            Slider(value: $value, in: 0...1) { Text(label) }
        }
    }

    /// The slider `width` across, drawn `Give.limit` in from the canvas's left edge.
    private func draw(_ context: inout GraphicsContext, width: Double, height: Double, stretch s: Double) {
        let r = Self.thumb, y = height / 2, inset = Give.limit
        let start = inset + r + min(s, 0), end = inset + width - r + max(s, 0)
        let x = start + (end - start) * value
        // A little thinner as it stretches.
        let track = Self.track * (1 - 0.3 * abs(s) / Give.limit)
        func line(_ a: Double, _ b: Double) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: a, y: y))
            p.addLine(to: CGPoint(x: b, y: y))
            return p
        }
        let round = StrokeStyle(lineWidth: track, lineCap: .round)
        context.stroke(line(start, end), with: .color(.primary.opacity(0.18)), style: round)
        context.stroke(line(start, x), with: .color(.accentColor), style: round)
        let knob = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
        var shadowed = context
        shadowed.addFilter(.shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5))
        shadowed.fill(knob, with: .color(.white))
        context.stroke(knob, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
    }

    private func drag(width: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, touching, _ in touching = true }
            .onChanged { v in
                let r = Self.thumb
                let x = Double(v.location.x)
                let at = min(max((x - r) / (width - 2 * r), 0), 1)
                value = at
                let end = at == 0 || at == 1
                if !dragging {
                    // Pressed: it goes to the pointer, without a tick even at an end.
                    dragging = true
                    atEnd = end
                    return
                }
                if end && !atEnd { HapticManager.shared.tick() }
                atEnd = end
                give.drag(past: min(x - r, 0) + max(x - (width - r), 0), at: MediaClock.now())
            }
            .onEnded { _ in
                dragging = false
                give.release(at: MediaClock.now())
            }
    }
}

/// "2:40"
func clockText(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

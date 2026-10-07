//
//  Controls.swift
//  BreatheFree
//
//  Buttons, the session-length picker and the sound picker, styled to sit on the sky in the
//  colours the sky calls for (Ink).
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
struct CyclePicker: View {
    let choices: [Int]
    @Binding var selection: Int
    @Binding var open: Bool
    let describe: (Int) -> String
    @Environment(\.ink) private var ink
    @Environment(\.pickerMoment) private var moment
    /// The drops' motion since the picker last opened or closed.
    @State private var motion: PickerMotion?

    private let size: CGFloat = 46
    private let gap: CGFloat = 8

    var body: some View {
        let chosen = choices.firstIndex(of: selection) ?? 0
        let width = CGFloat(choices.count) * size + CGFloat(choices.count - 1) * gap
        TimelineView(.animation) { _ in
            let now = MediaClock.now()
            let motion = drawnMotion(chosen: chosen, at: now)
            let drops = motion.drops(at: now, size: size, step: size + gap)
            ZStack {
                ForEach(choices.indices, id: \.self) { i in
                    count(i, drop: drops[i], chosen: chosen)
                }
            }
            .frame(width: width, height: size)
            .background {
                Canvas { context, canvas in
                    context.translateBy(x: canvas.width / 2, y: canvas.height / 2)
                    drawLiquid(&context, drops: drops, order: motion.order, settled: motion.isSettled(at: now))
                }
                .frame(width: width + 2 * size, height: 2 * size)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .onChange(of: open) { isOpen in
            // Folded from outside, by a click elsewhere or Escape: the drops go from where they are.
            let now = MediaClock.now()
            let before = motion ?? PickerMotion(count: choices.count, open: !isOpen, chosen: chosen)
            if before.opening != isOpen {
                motion = before.changed(open: isOpen, chosen: chosen, at: now)
            }
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

    private func count(_ i: Int, drop: PickerDrop, chosen: Int) -> some View {
        let n = choices[i]
        let current = i == chosen
        let shown = open || current
        return Button {
            press(i, chosen: chosen)
        } label: {
            Text("\(n)")
                .font(.system(size: 16, weight: current ? .semibold : .regular))
                .foregroundColor(ink.deep.mix(ink.onAccent, drop.accent).color)
                .opacity(drop.label)
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

    /// All the drops as one shape of liquid in the unchosen colours, run together wherever they
    /// meet, with a rim inside its edge, and the chosen one solid on top.
    private func drawLiquid(_ context: inout GraphicsContext, drops: [PickerDrop], order: [Int], settled: Bool) {
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
            for loop in LiquidOutline.loops(order.map { drops[$0].liquid }, inset: 0.5) {
                outline.move(to: CGPoint(x: loop[0].x, y: loop[0].y))
                for p in loop.dropFirst() {
                    outline.addLine(to: CGPoint(x: p.x, y: p.y))
                }
                outline.closeSubpath()
            }
            context.fill(outline, with: .color(ink.field.color), style: FillStyle(eoFill: true))
            context.stroke(outline, with: .color(ink.fieldBorder.color), lineWidth: 1)
        }
        for d in drops where d.accent > 0 && d.radius > 0.05 {
            let rect = CGRect(x: d.x - d.radius * d.stretch, y: -d.radius / d.stretch,
                              width: 2 * d.radius * d.stretch, height: 2 * d.radius / d.stretch)
            context.fill(Path(ellipseIn: rect), with: .color(ink.accent.color(d.accent)))
        }
    }
}

struct SegmentedChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.ink) private var ink

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let on = value == selection
                Button { selection = value } label: {
                    Text(options[i].1)
                        .font(.system(size: 14, weight: on ? .semibold : .regular))
                        .foregroundColor((on ? ink.onAccent : ink.deep).color)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(on ? ink.accent.color : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(maxWidth: 360)
        .background(Capsule().fill(ink.field.color))
        .overlay(Capsule().stroke(ink.fieldBorder.color, lineWidth: 1))
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

/// A see-through capsule with words on it, for an action a symbol alone leaves unclear.
struct PillButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.ink) private var ink

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(ink.deep.color)
                .padding(.horizontal, 16)
                .frame(height: 40)
                .background(Capsule().fill(ink.glass.color))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// "2:40"
func clockText(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

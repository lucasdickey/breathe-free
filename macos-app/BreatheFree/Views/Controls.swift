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

/// Session length as one circle showing the current count. Clicking it fans the other counts
/// out to its left and right, nearest first; clicking one picks it, and they fold back into
/// it. The home screen folds it too on a click anywhere else, and on Escape.
struct CyclePicker: View {
    let choices: [Int]
    @Binding var selection: Int
    @Binding var open: Bool
    let describe: (Int) -> String
    @Environment(\.ink) private var ink

    private let size: CGFloat = 46
    private let gap: CGFloat = 8

    var body: some View {
        let chosen = choices.firstIndex(of: selection) ?? 0
        ZStack {
            ForEach(choices.indices, id: \.self) { i in
                let n = choices[i]
                let current = i == chosen
                let shown = open || current
                let slot = (CGFloat(i) - CGFloat(choices.count - 1) / 2) * (size + gap)
                Button {
                    if open {
                        selection = n
                        open = false
                    } else {
                        open = true
                    }
                } label: {
                    Text("\(n)")
                        .font(.system(size: 16, weight: current ? .semibold : .regular))
                        .foregroundColor((current ? ink.onAccent : ink.deep).color)
                        .frame(width: size, height: size)
                        .background(Circle().fill((current ? ink.accent : ink.field).color))
                        .overlay(Circle().stroke((current ? ink.accent : ink.fieldBorder).color, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .scaleEffect(shown ? 1 : 0.55)
                .opacity(shown ? 1 : 0)
                .offset(x: open ? slot : 0)
                // The current count stays on top while the others come out from behind it.
                .zIndex(current ? 1 : 0)
                .allowsHitTesting(shown)
                .accessibilityHidden(!shown)
                .accessibilityLabel(open ? describe(n) : "Session length: \(describe(n)). Click to change.")
                .accessibilityAddTraits(open && current ? .isSelected : [])
                .animation(
                    open
                        ? Animation.spring(response: 0.42, dampingFraction: 0.68).delay(0.028 * Double(abs(i - chosen)))
                        : Animation.spring(response: 0.32, dampingFraction: 1),
                    value: open
                )
            }
        }
        .frame(width: CGFloat(choices.count) * size + CGFloat(choices.count - 1) * gap, height: size)
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

/// "2:40"
func clockText(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
}

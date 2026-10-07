//
//  Controls.swift
//  BreatheFree
//
//  Buttons, chips and the sound picker, styled to sit on the sky.
//

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var light = false

    func makeBody(configuration: Configuration) -> some View {
        let fill: Color
        if light {
            fill = Color.white.opacity(configuration.isPressed ? 0.8 : 0.95)
        } else {
            fill = configuration.isPressed ? Ink.accentPressed : Ink.accent
        }
        return configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(light ? Ink.deep : .white)
            .frame(maxWidth: 360)
            .frame(height: 50)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(.white)
            .frame(maxWidth: 360)
            .frame(height: 46)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.6), lineWidth: 1))
            .contentShape(Capsule())
    }
}

struct ChipButton: View {
    let text: String
    let selected: Bool
    let accessibility: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 16, weight: selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : Ink.deep)
                .frame(minWidth: 44, minHeight: 40)
                .padding(.horizontal, 6)
                .background(Capsule().fill(selected ? Ink.accent : Color.white.opacity(0.55)))
                .overlay(Capsule().stroke(selected ? Ink.accent : Color.white.opacity(0.85), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SegmentedChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                let on = value == selection
                Button { selection = value } label: {
                    Text(options[i].1)
                        .font(.system(size: 14, weight: on ? .semibold : .regular))
                        .foregroundColor(on ? .white : Ink.deep)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(on ? Ink.accent : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .frame(maxWidth: 360)
        .background(Capsule().fill(Color.white.opacity(0.45)))
        .overlay(Capsule().stroke(Color.white.opacity(0.85), lineWidth: 1))
    }
}

/// A round, see-through button for the session's top bar.
struct RoundIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color.white.opacity(0.12)))
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

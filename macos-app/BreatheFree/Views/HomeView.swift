//
//  HomeView.swift
//  BreatheFree
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var model: SessionModel
    @Environment(\.ink) private var ink
    /// Whether session length is fanned out.
    @State private var choosing: Bool

    init(model: SessionModel, choosing: Bool = false) {
        self.model = model
        _choosing = State(initialValue: choosing)
    }

    var body: some View {
        // Centred as is when the window is tall enough; scrolls only in a short window.
        ViewThatFits(in: .vertical) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView {
                content.frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        // While session length is open the other controls ignore clicks, so a click anywhere
        // but its circles lands here and folds it, and goes no further. Escape folds it too.
        .contentShape(Rectangle())
        .onTapGesture {
            if choosing { choosing = false }
        }
        .background {
            if choosing {
                Button("Close session length") { choosing = false }
                    .keyboardShortcut(.cancelAction)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            AmbientOrb(colors: ink.orb)
                .frame(width: 112, height: 112)
            Text("Breathe Free")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(ink.deep.color)
                .padding(.top, 4)

            label("Session length").padding(.top, 30)
            CyclePicker(choices: SessionPlan.cycleChoices, selection: $model.cycles, open: $choosing) { n in
                "\(n) cycles, \(clockText(n * Int(SessionPlan.cycleSeconds)))"
            }
            .padding(.top, 10)
            Text("\(model.cycles) cycles · \(clockText(model.cycles * Int(SessionPlan.cycleSeconds)))")
                .font(.system(size: 13))
                .foregroundColor(ink.soft.color)
                .padding(.top, 8)

            VStack(spacing: 0) {
                label("Sound").padding(.top, 22)
                SegmentedChoice(options: [(SoundMode.ambient, "Ambient"), (.bells, "Bells"), (.silent, "Silent")],
                                selection: $model.soundMode)
                    .padding(.top, 10)
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundColor(ink.soft.color)
                    Slider(value: $model.volume, in: 0...1)
                        .accessibilityLabel("Volume")
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(ink.soft.color)
                }
                .font(.system(size: 12))
                .frame(maxWidth: 360)
                .padding(.top, 14)
                .opacity(model.soundMode == .silent ? 0.4 : 1)
                .disabled(model.soundMode == .silent)

                Button("Begin", action: model.begin)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(choosing ? nil : KeyboardShortcut.defaultAction)
                    .padding(.top, 28)
            }
            .allowsHitTesting(!choosing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(ink.soft.color)
    }
}

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
            AmbientOrb(colors: ink.orb, sun: ink.sun)
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

                // Only what to hear here; how loud is set in the session, from the speaker.
                HStack {
                    Text("Voice guidance")
                        .font(.system(size: 13))
                        .foregroundColor(ink.deep.color)
                    Spacer()
                    Toggle("Voice guidance", isOn: $model.voiceOn)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .frame(maxWidth: 360)
                .padding(.top, 14)

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

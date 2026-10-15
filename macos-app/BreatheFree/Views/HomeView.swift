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
    /// Whether sound and voice are fanned out.
    @State private var settingsOpen: Bool

    init(model: SessionModel, choosing: Bool = false, settingsOpen: Bool = false) {
        self.model = model
        _choosing = State(initialValue: choosing)
        _settingsOpen = State(initialValue: settingsOpen)
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
        // While session length or sound and voice are open the other controls ignore clicks,
        // so a click anywhere but on what is open lands here and folds it, and goes no further.
        // Escape folds either too.
        .contentShape(Rectangle())
        .onTapGesture {
            choosing = false
            settingsOpen = false
        }
        // Sound and voice, folded into the button in the top-right corner.
        .overlay(alignment: .topTrailing) {
            SettingsFan(open: $settingsOpen, sound: $model.soundMode, voice: $model.voiceOn)
                .allowsHitTesting(!choosing)
        }
        // One open at a time: Command-comma opens sound and voice even while session length is.
        .onChange(of: settingsOpen) { open in
            if open { choosing = false }
        }
        .onChange(of: choosing) { open in
            if open { settingsOpen = false }
        }
        .background {
            if choosing || settingsOpen {
                Button("Close") {
                    choosing = false
                    settingsOpen = false
                }
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
                .padding(.top, 12)

            CyclePicker(choices: SessionPlan.cycleChoices, selection: $model.cycles, open: $choosing) { n in
                "\(n) cycles, \(clockText(n * Int(SessionPlan.cycleSeconds)))"
            }
            .allowsHitTesting(!settingsOpen)
            .padding(.top, 56)
            Text("\(model.cycles) cycles · \(clockText(model.cycles * Int(SessionPlan.cycleSeconds)))")
                .font(.system(size: 13))
                .foregroundColor(ink.soft.color)
                .padding(.top, 8)

            // Begin is the one thing to press, but it needn't span the window: a comfortable
            // width, centred.
            Button("Begin", action: model.begin)
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 240)
                .keyboardShortcut(choosing || settingsOpen ? nil : KeyboardShortcut.defaultAction)
                .allowsHitTesting(!choosing && !settingsOpen)
                .padding(.top, 40)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
    }
}

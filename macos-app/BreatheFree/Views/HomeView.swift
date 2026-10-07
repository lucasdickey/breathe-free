//
//  HomeView.swift
//  BreatheFree
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    AmbientOrb(colors: .day)
                        .frame(width: 112, height: 112)
                    Text("Breathe Free")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(Ink.deep)
                        .padding(.top, 4)
                    Text("Box breathing: in, hold, out, hold.\nFour counts each.")
                        .font(.system(size: 15))
                        .foregroundColor(Ink.soft)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)

                    label("Session length").padding(.top, 28)
                    HStack(spacing: 6) {
                        ForEach(SessionPlan.cycleChoices, id: \.self) { n in
                            ChipButton(text: "\(n)", selected: n == model.cycles,
                                       accessibility: "\(n) cycles, \(clockText(n * Int(SessionPlan.cycleSeconds)))") {
                                model.cycles = n
                            }
                        }
                    }
                    .padding(.top, 10)
                    Text("\(model.cycles) cycles · \(clockText(model.cycles * Int(SessionPlan.cycleSeconds)))")
                        .font(.system(size: 13))
                        .foregroundColor(Ink.soft)
                        .padding(.top, 8)

                    label("Sound").padding(.top, 22)
                    SegmentedChoice(options: [(SoundMode.ambient, "Ambient"), (.bells, "Bells"), (.silent, "Silent")],
                                    selection: $model.soundMode)
                        .padding(.top, 10)
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill").foregroundColor(Ink.soft)
                        Slider(value: $model.volume, in: 0...1)
                            .accessibilityLabel("Volume")
                        Image(systemName: "speaker.wave.3.fill").foregroundColor(Ink.soft)
                    }
                    .font(.system(size: 12))
                    .frame(maxWidth: 360)
                    .padding(.top, 14)
                    .opacity(model.soundMode == .silent ? 0.4 : 1)
                    .disabled(model.soundMode == .silent)

                    Button("Begin", action: model.begin)
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .padding(.top, 28)
                    Text("Sit comfortably. Headphones bring the sound closer.")
                        .font(.system(size: 12))
                        .foregroundColor(Ink.soft.opacity(0.85))
                        .padding(.top, 12)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, minHeight: geo.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.4)
            .foregroundColor(Ink.soft)
    }
}

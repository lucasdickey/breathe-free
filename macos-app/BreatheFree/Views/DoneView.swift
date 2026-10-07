//
//  DoneView.swift
//  BreatheFree
//

import SwiftUI

struct DoneView: View {
    @ObservedObject var model: SessionModel

    var body: some View {
        let cycles = model.session?.plan.cycles ?? model.cycles
        VStack(spacing: 0) {
            AmbientOrb(colors: .night, period: 12, depth: 0.6)
                .frame(width: 140, height: 140)
            Text("Well done")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(.white)
                .padding(.top, 10)
            Text("Be easy. Breathe deeply.")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.88))
                .padding(.top, 8)
            Text("\(cycles) cycles · \(clockText(cycles * Int(SessionPlan.cycleSeconds))) of box breathing")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
                .padding(.top, 6)
            Button("Done", action: model.backHome)
                .buttonStyle(PrimaryButtonStyle(light: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 36)
            Button("Breathe again", action: model.begin)
                .buttonStyle(OutlineButtonStyle())
                .padding(.top, 12)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

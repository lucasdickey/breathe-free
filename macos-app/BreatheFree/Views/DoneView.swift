//
//  DoneView.swift
//  BreatheFree
//

import SwiftUI

struct DoneView: View {
    @ObservedObject var model: SessionModel
    @Environment(\.ink) private var ink

    var body: some View {
        let cycles = model.session?.plan.cycles ?? model.cycles
        VStack(spacing: 0) {
            AmbientOrb(colors: ink.orb, period: 12, depth: 0.6)
                .frame(width: 140, height: 140)
            Text("Well done")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(ink.deep.color)
                .padding(.top, 10)
            Text("Be easy. Breathe deeply.")
                .font(.system(size: 18))
                .foregroundColor(ink.deep.color)
                .padding(.top, 8)
            Text("\(cycles) cycles · \(clockText(cycles * Int(SessionPlan.cycleSeconds))) of box breathing")
                .font(.system(size: 13))
                .foregroundColor(ink.soft.color)
                .padding(.top, 6)
            Button("Done", action: model.backHome)
                .buttonStyle(PrimaryButtonStyle())
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

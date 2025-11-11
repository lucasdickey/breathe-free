//
//  BalloonView.swift
//  BreatheFree
//
//  Animated balloon component that scales with breathing
//

import SwiftUI

struct BalloonView: View {
    let state: BreathingState
    let countdown: Int
    @State private var scale: CGFloat = 1.0

    var body: some View {
        ZStack {
            // Balloon circle
            Circle()
                .fill(balloonColor)
                .frame(width: 256, height: 256)
                .scaleEffect(scale)
                .animation(
                    .easeInOut(duration: state.isActiveBreathing ? 4.0 : 0.3),
                    value: scale
                )

            VStack(spacing: 8) {
                // Prompt text
                Text(state.displayText)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .opacity(textOpacity)
                    .animation(.easeInOut(duration: 0.2), value: state)

                // Countdown display
                if state.isActiveBreathing || state == .preStart {
                    Text("\(countdown)")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(textColor)
                        .opacity(textOpacity)
                        .animation(.easeInOut(duration: 0.2), value: countdown)
                }
            }
        }
        .onChange(of: state) { _, newState in
            updateScale(for: newState)
        }
        .onAppear {
            updateScale(for: state)
        }
    }

    private var balloonColor: Color {
        if state == .idle || state == .completed {
            return .white
        } else {
            return Color(red: 0.024, green: 0.714, blue: 0.831) // Cyan #06b6d4
        }
    }

    private var textColor: Color {
        if state == .idle || state == .completed {
            return Color(red: 0.122, green: 0.161, blue: 0.216) // Dark gray #1f2937
        } else {
            return .white
        }
    }

    private var textOpacity: Double {
        state == .idle ? 0 : 1
    }

    private func updateScale(for newState: BreathingState) {
        if newState.shouldScaleBalloon {
            scale = 2.0
        } else {
            scale = 1.0
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        BalloonView(state: .idle, countdown: 0)
        BalloonView(state: .breatheIn, countdown: 4)
        BalloonView(state: .holdIn, countdown: 3)
    }
    .padding()
    .frame(width: 600, height: 800)
}

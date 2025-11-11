//
//  ContentView.swift
//  BreatheFree
//
//  Main breathing exercise interface
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioManager = AudioManager()
    @State private var breathingState: BreathingState = .idle
    @State private var countdown: Int = 0
    @State private var selectedCycles: Int = 10
    @State private var currentCycle: Int = 0
    @State private var totalDuration: Int = 0
    @State private var sessionDuration: Int = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(red: 0.941, green: 0.976, blue: 1.0), // #f0f9ff
                    Color(red: 0.902, green: 0.949, blue: 1.0), // #e6f2ff
                    Color(red: 0.8, green: 0.902, blue: 1.0)    // #cce6ff
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Animated clouds
            CloudBackgroundView()

            // Main content
            if breathingState == .idle {
                idleView
            } else if breathingState == .completed {
                completedView
            } else {
                activeBreathingView
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    // MARK: - Idle View (Home Screen)
    private var idleView: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 24) {
                // Breathing icon
                ZStack {
                    ForEach(0..<3) { index in
                        Circle()
                            .stroke(
                                Color(red: 0.024, green: 0.714, blue: 0.831),
                                lineWidth: 2
                            )
                            .frame(width: CGFloat(80 + index * 30), height: CGFloat(80 + index * 30))
                            .opacity(0.7 - Double(index) * 0.2)
                    }
                }
                .frame(height: 140)

                // Title
                Text("Breathe")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(Color(red: 0.122, green: 0.161, blue: 0.216))

                // Subtitle
                Text("Find your calm through guided breathing")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))
                    .multilineTextAlignment(.center)

                // Instructions
                Text("Box breathing: Inhale • Hold • Exhale • Hold")
                    .font(.system(size: 16))
                    .foregroundColor(Color(red: 0.42, green: 0.447, blue: 0.502))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .padding(40)
            .frame(maxWidth: 512)
            .background(Color.white.opacity(0.9))
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.1), radius: 12, x: 0, y: 4)

            // Cycle selector
            CycleDropdownView(selectedCycles: $selectedCycles)
                .padding(.horizontal, 40)

            // Begin button
            Button(action: startBreathing) {
                Text("Begin Session")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 512)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.024, green: 0.714, blue: 0.831))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.horizontal, 40)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Active Breathing View
    private var activeBreathingView: some View {
        ZStack {
            // Background color for active state
            if breathingState.isActiveBreathing || breathingState == .preStart {
                Color(red: 0.024, green: 0.714, blue: 0.831)
                    .ignoresSafeArea()

                // Animated clouds
                CloudBackgroundView()
            }

            VStack {
                // Top bar with timer and close button
                HStack {
                    Spacer()

                    // Timer display (remaining time)
                    if breathingState.isActiveBreathing {
                        HStack(spacing: 12) {
                            Image(systemName: "clock")
                                .font(.system(size: 16))
                                .foregroundColor(.white)

                            Text(formatTime(sessionDuration - totalDuration))
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(20)
                    }

                    // Audio controls
                    AudioControlsView(audioManager: audioManager)

                    // Close button
                    Button(action: stopBreathing) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 40, height: 40)
                            .background(Color.white.opacity(0.2))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(24)

                Spacer()

                // Balloon
                BalloonView(state: breathingState, countdown: countdown)

                Spacer()

                // Cycle progress (only during active breathing)
                if breathingState.isActiveBreathing {
                    Text("Cycle \(currentCycle) of \(selectedCycles)")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.bottom, 40)
                }
            }
        }
    }

    // MARK: - Completed View
    private var completedView: some View {
        VStack(spacing: 40) {
            Spacer()

            BalloonView(state: .completed, countdown: 0)

            Button(action: {
                breathingState = .idle
                currentCycle = 0
                totalDuration = 0
            }) {
                Text("Back to Start")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: 300)
                    .padding(.vertical, 16)
                    .background(Color(red: 0.024, green: 0.714, blue: 0.831))
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(PlainButtonStyle())

            Spacer()
        }
    }

    // MARK: - Breathing Logic

    private func startBreathing() {
        breathingState = .preStart
        countdown = breathingState.duration
        currentCycle = 1
        totalDuration = 0
        // Calculate total session duration: 8 seconds pre-start + (4*4 seconds per cycle)
        sessionDuration = 8 + (selectedCycles * 16)

        // Trigger initial haptic
        HapticManager.shared.triggerHaptic(for: .preStart)

        // Start timer
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            tick()
        }
    }

    private func stopBreathing() {
        timer?.invalidate()
        timer = nil
        audioManager.stopAudio()
        breathingState = .idle
        currentCycle = 0
        totalDuration = 0
    }

    private func tick() {
        countdown -= 1

        // Track total duration during active breathing
        if breathingState.isActiveBreathing {
            totalDuration += 1
        }

        if countdown <= 0 {
            // Move to next state
            let previousState = breathingState
            breathingState = breathingState.nextState

            // Check if we've completed all cycles
            if breathingState == .breatheIn && currentCycle >= selectedCycles {
                breathingState = .completed
                timer?.invalidate()
                timer = nil
                audioManager.stopAudio()
                HapticManager.shared.triggerHaptic(for: .completed)
                return
            }

            // Increment cycle counter when starting a new cycle
            if breathingState == .breatheIn && previousState == .holdOut {
                currentCycle += 1
            }

            // Set new countdown
            countdown = breathingState.duration

            // Trigger haptic feedback
            HapticManager.shared.triggerHaptic(for: breathingState)

            // Start audio on breathe in phase
            if breathingState == .breatheIn {
                audioManager.playAudio()
            }
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let mins = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .frame(width: 800, height: 600)
    }
}
#endif

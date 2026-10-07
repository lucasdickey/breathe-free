//
//  SessionView.swift
//  BreatheFree
//
//  The session: everything on screen is computed afresh each frame from the session
//  clock, so nothing can lag behind or drift from the sound.
//

import SwiftUI
import QuartzCore

struct SessionView: View {
    @ObservedObject var model: SessionModel
    let session: ActiveSession
    @State private var showVolume = false
    @Environment(\.ink) private var ink

    /// A frame drawn now reaches the screen about one refresh later; aim the picture there.
    static let displayLead = 1.0 / 60.0

    var body: some View {
        GeometryReader { geo in
            let g = SceneGeometry.of(geo.size)
            TimelineView(.animation) { _ in
                let t = session.time(at: MediaClock.now() + Self.displayLead)
                let frame = session.plan.frame(at: t)
                // Paused, the session clock stands still, so all of this holds where it is.
                let paused = session.isPaused
                ZStack {
                    Group {
                        Canvas { context, _ in
                            SceneDrawing.session(&context, geometry: g, frame: frame, time: t, ink: ink)
                        }
                        .accessibilityHidden(true)

                        if frame.countdown > 0 {
                            Text("\(frame.countdown)")
                                .font(.system(size: 30, weight: .light).monospacedDigit())
                                // Dark on the lit orb: white disappears into its bright centre.
                                .foregroundColor(Ink.countdown.color(frame.stage == .settle ? 0.55 : 0.8))
                                .position(x: g.cx, y: g.cy)
                                .accessibilityHidden(true)
                        }
                    }
                    .opacity(paused ? 0.45 : 1)

                    if paused {
                        Text("Paused")
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(ink.deep.color)
                            .position(x: g.cx, y: g.cy + g.half + 58)
                        Text("Press Space to carry on")
                            .font(.system(size: 15))
                            .foregroundColor(ink.soft.color)
                            .position(x: g.cx, y: g.cy + g.half + 96)
                    } else {
                        // The words before fade out as the new ones fade in, each centred on
                        // its own, both worked out from the session clock like everything else.
                        let words = session.plan.prompt(at: t)
                        Text(words.previous)
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(ink.deep.color)
                            .opacity(1 - words.fade)
                            .position(x: g.cx, y: g.cy + g.half + 58)
                            .accessibilityHidden(true)
                        Text(words.text)
                            .font(.system(size: 30, weight: .light))
                            .foregroundColor(ink.deep.color)
                            .opacity(words.fade)
                            .position(x: g.cx, y: g.cy + g.half + 58)
                            .accessibilityAddTraits(.updatesFrequently)

                        if frame.stage == .settle {
                            Text("Soften your shoulders and jaw")
                                .font(.system(size: 15))
                                .foregroundColor(ink.soft.color)
                                .position(x: g.cx, y: g.cy + g.half + 96)
                        }
                    }

                    VStack(spacing: 10) {
                        Text(frame.stage == .settle ? "Starting soon" : "Cycle \(min(frame.cycle + 1, session.plan.cycles)) of \(session.plan.cycles)")
                            .font(.system(size: 13))
                            .foregroundColor(ink.soft.color)
                        progressBar(done: 1 - frame.remaining / session.plan.breathingSeconds)
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 26)

                    Text(clockText(Int((frame.remaining - 1e-9).rounded(.up))))
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundColor(ink.deep.color)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 22)
                        .accessibilityLabel("\(clockText(Int(frame.remaining.rounded(.up)))) left")
                }
                .animation(.easeInOut(duration: 0.35), value: paused)
            }
            topBar
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()
            // For when someone walks in: everything holds still until it is pressed again.
            RoundIconButton(systemImage: session.isPaused ? "play.fill" : "pause.fill",
                            label: session.isPaused ? "Resume session" : "Pause session",
                            action: model.togglePause)
                .keyboardShortcut(.space, modifiers: [])
            RoundIconButton(systemImage: soundSymbol, label: "Sound: \(model.sessionSound.label). Click to change.") {
                model.nextSessionSound()
            }
            RoundIconButton(systemImage: "slider.horizontal.3", label: "Volume") { showVolume.toggle() }
                .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                    HStack(spacing: 10) {
                        Image(systemName: "speaker.fill")
                        Slider(value: $model.volume, in: 0...1).frame(width: 180)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .padding(16)
                }
            // Words rather than an ✕, which reads as closing a panel, not ending the session.
            PillButton(title: "End session", action: model.endSession)
                .keyboardShortcut(.cancelAction)
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
    }

    private var soundSymbol: String {
        switch model.sessionSound {
        case .ambient: return "speaker.wave.2.fill"
        case .bells: return "bell.fill"
        case .silent: return "speaker.slash.fill"
        }
    }

    private func progressBar(done: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(ink.line.color(0.18))
            Capsule().fill(ink.line.color(0.7)).frame(width: 160 * min(max(done, 0), 1))
        }
        .frame(width: 160, height: 3)
    }
}

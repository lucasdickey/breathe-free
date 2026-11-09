//
//  Snapshots.swift
//
//  Renders the app's screens to PNG without launching the app, so layout changes can be
//  checked on any Mac or in CI. Compiled together with the app's sources:
//
//    swiftc -parse-as-library -o snapshots macos-app/BreatheFree/{Core,Audio,Models,Views}/*.swift \
//      macos-app/Snapshots/Snapshots.swift && ./snapshots <output folder>
//
//  The sky is the one for set times on 7 October 2026 in Los Angeles, so every run matches.
//

import AppKit
import QuartzCore
import SwiftUI

/// The sky for one moment, held still.
private struct StillSky: View {
    let sky: SkyPalette

    var body: some View {
        Canvas { context, size in
            SceneDrawing.sky(&context, size: size, palette: sky)
            StarField.shared.draw(in: &context, size: size, time: 40, amount: sky.stars)
            let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
            CloudField.shared.draw(in: &context, size: size, time: 40, palette: sky, sprite: sprite)
        }
    }
}

@main
struct Snapshots {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        let size = CGSize(width: 960, height: 760)
        let model = SessionModel()
        let zone = TimeZone(identifier: "America/Los_Angeles")!

        func at(_ hour: Int, _ minute: Int) -> DayLook {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: hour, minute: minute))!
            return DaySky.look(at: date, in: zone)
        }

        func shoot<V: View>(_ name: String, _ look: DayLook, _ view: V) {
            let scene = ZStack {
                StillSky(sky: look.sky)
                view
            }
            .environment(\.ink, Ink.matching(look))
            .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: scene)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                print("could not render \(name)")
                return
            }
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
            do {
                try png.write(to: url)
                print("wrote \(url.path)")
            } catch {
                print("could not write \(url.path): \(error)")
            }
        }

        func session(at t: Double) -> ActiveSession {
            ActiveSession(plan: SessionPlan(cycles: 2), startTime: CACurrentMediaTime() - t)
        }

        let noon = at(12, 30)
        let sunset = at(18, 40)
        let night = at(20, 49)

        shoot("1-home-noon", noon, HomeView(model: model))
        shoot("1-home-sunset", sunset, HomeView(model: model))
        shoot("1-home-night", night, HomeView(model: model))
        shoot("1-home-session-length-open", noon, HomeView(model: model, choosing: true))
        shoot("1-home-session-length-open-night", night, HomeView(model: model, choosing: true))
        // Sound, voice and focus mode fanned out of the corner: all on, then all off.
        let (sound, voice, focus) = (model.soundMode, model.voiceOn, model.focusOn)
        model.focusOn = true
        shoot("1-home-settings-open", noon, HomeView(model: model, settingsOpen: true))
        shoot("1-home-settings-open-night", night, HomeView(model: model, settingsOpen: true))
        model.soundMode = .silent
        model.voiceOn = false
        model.focusOn = false
        shoot("1-home-settings-off", noon, HomeView(model: model, settingsOpen: true))
        shoot("1-home-settings-off-night", night, HomeView(model: model, settingsOpen: true))
        model.soundMode = sound
        model.voiceOn = voice
        model.focusOn = focus
        // The opening: the drop gathering, necking, falling and landing, and the orb settled with its count.
        for (name, t) in [("1-gathering", 3.0), ("2-necking", 4.05), ("3-falling", 4.4), ("4-landing", 4.62),
                          ("5-settled", 6.0)] {
            shoot("2-drip-\(name)-noon", noon, SessionView(model: model, session: session(at: t)))
            shoot("2-drip-\(name)-night", night, SessionView(model: model, session: session(at: t)))
        }
        for (name, t) in [("2-settle", 3.0), ("3-inhale", 9.9), ("4-hold", 13.6), ("5-exhale", 17.6)] {
            shoot("\(name)-night", night, SessionView(model: model, session: session(at: t)))
        }
        shoot("3-inhale-noon", noon, SessionView(model: model, session: session(at: 9.9)))
        // The gust from Hold to Breathe out: Hold starting to leave, the two words crossing, and
        // Breathe out landing just after its phase begins.
        for (name, t) in [("leaving", 15.4), ("crossing", 15.75), ("landing", 16.3)] {
            shoot("5-gust-\(name)-noon", noon, SessionView(model: model, session: session(at: t)))
            shoot("5-gust-\(name)-night", night, SessionView(model: model, session: session(at: t)))
        }
        // Focus mode, a few seconds into the inhale: the top bar and the count out of sight.
        model.focusOn = true
        shoot("3-inhale-focus-noon", noon, SessionView(model: model, session: session(at: 9.9), controlsShown: false))
        shoot("3-inhale-focus-night", night, SessionView(model: model, session: session(at: 9.9), controlsShown: false))
        model.focusOn = focus
        // Paused part way through a hold: the scene dims and the words give way to "Paused".
        let now = CACurrentMediaTime()
        let held = ActiveSession(plan: SessionPlan(cycles: 2), startTime: now - 13.6).paused(at: now)
        shoot("4-hold-paused-noon", noon, SessionView(model: model, session: held))
        shoot("4-hold-paused-night", night, SessionView(model: model, session: held))
        // End session open, waiting for the second click.
        shoot("4-hold-end-open-noon", noon, SessionView(model: model, session: session(at: 13.6), endOpen: true))
        shoot("4-hold-end-open-night", night, SessionView(model: model, session: session(at: 13.6), endOpen: true))
        shoot("6-done-night", night, DoneView(model: model))
        shoot("6-done-noon", noon, DoneView(model: model))
        // The gestures (Gestures.swift). The orb pulled down and to the right, then let go: just
        // after, overshooting, wobbling, and its ring spreading. As Android's ScreenshotTest.theOrbCanBePoked.
        func poke(letGoAgo: Double?) -> OrbPoke {
            var p = OrbPoke(side: 112, still: false)
            let now = CACurrentMediaTime()
            let t0 = now - (letGoAgo ?? 0) - 0.176
            p.down(.zero, at: t0)
            for i in 1...10 { p.move(SIMD2(12, 10) * Double(i), at: t0 + 0.016 * Double(i)) }
            if let ago = letGoAgo { p.up(at: now - ago, radius: 112 * 0.25) }
            return p
        }
        shoot("8-poke-1-pulled-noon", noon, HomeView(model: model, poked: poke(letGoAgo: nil)))
        shoot("8-poke-1-pulled-night", night, HomeView(model: model, poked: poke(letGoAgo: nil)))
        for (name, ago) in [("2-let-go", 0.07), ("3-overshoot", 0.16), ("4-wobble", 0.3), ("5-ring", 1.0)] {
            shoot("8-poke-\(name)-noon", noon, HomeView(model: model, poked: poke(letGoAgo: ago)))
        }
        // The session length slid from 6: between 10 and 20, over 20, and held back past 50.
        let cycles = model.cycles
        model.cycles = 6
        let choices = SessionPlan.cycleChoices
        let row = BeadSlide(count: choices.count, step: 54, size: 46, pointer: 0)
        for (name, steps) in [("1-between", 1.5), ("2-over-20", 2.0), ("3-held-back-past-50", 6.0)] {
            var slide = BeadSlide(count: choices.count, step: 54, size: 46, pointer: row.slot(1))
            let now = CACurrentMediaTime()
            for i in 1...8 { slide.move(row.slot(1) + 54 * steps * Double(i) / 8, at: now - 0.2 + 0.025 * Double(i)) }
            shoot("8-slide-\(name)-noon", noon, HomeView(model: model, slid: slide))
            shoot("8-slide-\(name)-night", night, HomeView(model: model, slid: slide))
        }
        model.cycles = cycles
        // The ✕ held half way: open, saying what to do, and half full.
        shoot("8-hold-to-end-noon", noon, SessionView(model: model, session: session(at: 13.6), endHeld: 0.55))
        shoot("8-hold-to-end-night", night, SessionView(model: model, session: session(at: 13.6), endHeld: 0.55))
        // The volume slider at rest at its end, and pulled on past it (as in its popover).
        let panel = VStack(spacing: 18) {
            ForEach([0.0, 6.5, -6.5], id: \.self) { stretch in
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill")
                    GiveSlider(value: .constant(stretch < 0 ? 0 : 1), label: "Volume", stretched: stretch)
                        .frame(width: 180)
                    Image(systemName: "speaker.wave.3.fill")
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: 0.96)))
        .environment(\.colorScheme, .light)
        shoot("8-volume-gives", noon, panel)

        // The orb in each sky's own colours through the day, holding full and holding empty.
        for (name, hour, minute) in [("1-first-light", 6, 50), ("2-sunrise", 7, 15), ("3-morning", 8, 30),
                                     ("4-noon", 12, 30), ("5-golden", 17, 35), ("6-sunset", 18, 40),
                                     ("7-last-light", 18, 58), ("8-dusk", 19, 25), ("9-night", 20, 49)] {
            shoot("7-orb-\(name)-full", at(hour, minute), SessionView(model: model, session: session(at: 13.6)))
            shoot("7-orb-\(name)-empty", at(hour, minute), SessionView(model: model, session: session(at: 21.6)))
        }
    }
}

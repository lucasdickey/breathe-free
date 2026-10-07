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
    var level = 0.0

    var body: some View {
        Canvas { context, size in
            SceneDrawing.sky(&context, size: size, palette: sky, level: level)
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

        func shoot<V: View>(_ name: String, _ look: DayLook, level: Double = 0, _ view: V) {
            let scene = ZStack {
                StillSky(sky: look.sky, level: level)
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

        func session(at t: Double) -> (ActiveSession, Double) {
            let session = ActiveSession(plan: SessionPlan(cycles: 2), startTime: CACurrentMediaTime() - t)
            return (session, session.plan.frame(at: t).level)
        }

        let noon = at(12, 30)
        let sunset = at(18, 40)
        let night = at(20, 49)

        shoot("1-home-noon", noon, HomeView(model: model))
        shoot("1-home-sunset", sunset, HomeView(model: model))
        shoot("1-home-night", night, HomeView(model: model))
        shoot("1-home-session-length-open", noon, HomeView(model: model, choosing: true))
        shoot("1-home-session-length-open-night", night, HomeView(model: model, choosing: true))
        for (name, t) in [("2-settle", 3.0), ("3-inhale", 9.9), ("4-hold", 13.6), ("5-exhale", 17.6)] {
            let (s, level) = session(at: t)
            shoot("\(name)-night", night, level: level, SessionView(model: model, session: s))
        }
        let (s, level) = session(at: 9.9)
        shoot("3-inhale-noon", noon, level: level, SessionView(model: model, session: s))
        // Paused part way through a hold: the scene dims and the words give way to "Paused".
        let now = CACurrentMediaTime()
        let held = ActiveSession(plan: SessionPlan(cycles: 2), startTime: now - 13.6).paused(at: now)
        let heldLevel = held.plan.frame(at: held.time(at: now)).level
        shoot("4-hold-paused-noon", noon, level: heldLevel, SessionView(model: model, session: held))
        shoot("4-hold-paused-night", night, level: heldLevel, SessionView(model: model, session: held))
        shoot("6-done-night", night, DoneView(model: model))
        shoot("6-done-noon", noon, DoneView(model: model))
    }
}

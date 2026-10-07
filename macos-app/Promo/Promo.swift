//
//  Promo.swift
//
//  Renders the Mac app's frames for the 30-second promo (promo/README.md), following
//  promo/script.json: the home screen as the sky sweeps from morning to night, session length
//  opened and a count picked, Begin, then a whole breathing cycle at its true pace. The app's
//  own views draw every frame, with the media clock held at the frame's moment. Compiled
//  together with the app's sources on a Mac:
//
//    swiftc -parse-as-library -O -o render-promo macos-app/BreatheFree/{Core,Audio,Models,Views}/*.swift \
//      macos-app/Promo/Promo.swift && ./render-promo promo/script.json <output folder>
//

import AppKit
import SwiftUI

private struct Script: Decodable {
    struct Sweep: Decodable {
        let start: Double
        let end: Double
        let fromHour: Double
        let toHour: Double
    }

    struct Cycles: Decodable {
        let before: Int
        let picked: Int
    }

    struct Taps: Decodable {
        let open: Double
        let pick: Double
        let begin: Double
    }

    struct Session: Decodable {
        let lagSeconds: Double
    }

    let fps: Int
    let seconds: Double
    let date: String
    let zone: String
    let sweep: Sweep
    let cycles: Cycles
    let taps: Taps
    let session: Session
}

/// The sky for one moment, with its clouds and stars where they are at `time`.
private struct StillSky: View {
    let sky: SkyPalette
    let time: Double
    var level = 0.0

    var body: some View {
        Canvas { context, size in
            SceneDrawing.sky(&context, size: size, palette: sky, level: level)
            StarField.shared.draw(in: &context, size: size, time: time, amount: sky.stars)
            let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
            CloudField.shared.draw(in: &context, size: size, time: time, palette: sky, sprite: sprite)
        }
    }
}

@main
struct Promo {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let arguments = CommandLine.arguments
        guard arguments.count > 2,
              let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[1])),
              let script = try? JSONDecoder().decode(Script.self, from: data) else {
            print("usage: promo <script.json> <output folder>")
            exit(1)
        }
        let folder = URL(fileURLWithPath: arguments[2])
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let size = CGSize(width: 1280, height: 800)
        let zone = TimeZone(identifier: script.zone)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let day = script.date.split(separator: "-").compactMap { Int($0) }
        let midnight = calendar.date(from: DateComponents(year: day[0], month: day[1], day: day[2]))!

        // The sky's time of day eases from morning to night across the opening seconds.
        func hour(at v: Double) -> Double {
            let x = min(max((v - script.sweep.start) / (script.sweep.end - script.sweep.start), 0), 1)
            return script.sweep.fromHour + (script.sweep.toHour - script.sweep.fromHour) * x * x * (3 - 2 * x)
        }

        let model = SessionModel()
        model.soundMode = .ambient
        model.cycles = script.cycles.before
        // With the clock at v the session is at v - lag, as in the Android renderer.
        let lag = script.session.lagSeconds
        let session = ActiveSession(plan: SessionPlan(cycles: script.cycles.picked),
                                    startTime: lag + SessionView.displayLead)

        let frames = Int((script.seconds * Double(script.fps)).rounded())
        for k in 0..<frames {
            // Let go of each frame's images before drawing the next, not all at the end.
            autoreleasepool {
                let v = Double(k) / Double(script.fps)
                MediaClock.fixed = v
                let look = DaySky.look(at: midnight.addingTimeInterval(hour(at: v) * 3600), in: zone)
                let scene: AnyView
                if v < script.taps.begin {
                    model.cycles = v >= script.taps.pick ? script.cycles.picked : script.cycles.before
                    let open = v >= script.taps.open && v < script.taps.pick
                    // Session length moves from its last open or pick, as it does when clicked.
                    let before = SessionPlan.cycleChoices.firstIndex(of: script.cycles.before) ?? 0
                    let changed: Double? = v >= script.taps.pick ? script.taps.pick : v >= script.taps.open ? script.taps.open : nil
                    scene = AnyView(ZStack {
                        StillSky(sky: look.sky, time: v)
                        HomeView(model: model, choosing: open)
                            .environment(\.pickerMoment, changed.map { PickerMoment(changedAt: $0, previous: before) })
                    })
                } else {
                    let level = session.plan.frame(at: v - lag).level
                    scene = AnyView(ZStack {
                        StillSky(sky: look.sky, time: v, level: level)
                        SessionView(model: model, session: session)
                    })
                }
                let renderer = ImageRenderer(content: scene
                    .environment(\.ink, Ink.matching(look))
                    .frame(width: size.width, height: size.height))
                renderer.scale = 1.25
                guard let image = renderer.cgImage,
                      let jpeg = NSBitmapImageRep(cgImage: image)
                          .representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
                    print("could not render frame \(k)")
                    exit(1)
                }
                do {
                    try jpeg.write(to: folder.appendingPathComponent(String(format: "f%05d.jpg", k)))
                } catch {
                    print("could not write frame \(k): \(error)")
                    exit(1)
                }
                if k % 150 == 0 { print("frame \(k) of \(frames)") }
            }
        }
        print("wrote \(frames) frames to \(folder.path)")
    }
}

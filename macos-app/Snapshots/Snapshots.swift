//
//  Snapshots.swift
//
//  Renders the app's screens to PNG without launching the app, so layout changes can be
//  checked on any Mac or in CI. Compiled together with the app's sources:
//
//    swiftc -parse-as-library -o snapshots macos-app/BreatheFree/{Core,Audio,Models,Views}/*.swift \
//      macos-app/Snapshots/Snapshots.swift && ./snapshots <output folder>
//

import AppKit
import QuartzCore
import SwiftUI

/// The sky for a given mood, without the cross-fade the live app uses.
private struct StillSky: View {
    let mood: SkyMood
    var level = 0.0

    var body: some View {
        Canvas { context, size in
            SceneDrawing.sky(&context, size: size, palette: mood.palette, level: level)
            let sprite = context.resolve(Image(decorative: CloudField.puff, scale: 1))
            CloudField.shared.draw(in: &context, size: size, time: 40, palette: mood.palette, sprite: sprite)
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

        func shoot<V: View>(_ name: String, _ view: V) {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
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

        shoot("1-home", ZStack { StillSky(mood: .day); HomeView(model: model) })
        for (name, t) in [("2-settle", 3.0), ("3-inhale", 9.9), ("4-hold", 13.6), ("5-exhale", 17.6)] {
            let session = ActiveSession(plan: SessionPlan(cycles: 2), startTime: CACurrentMediaTime() - t)
            let level = session.plan.frame(at: t).level
            shoot(name, ZStack { StillSky(mood: .dusk, level: level); SessionView(model: model, session: session) })
        }
        shoot("6-done", ZStack { StillSky(mood: .dawn); DoneView(model: model) })
    }
}

//
//  Drive.swift
//
//  Works the app's gestures in a real window with the mouse and keys, as someone would, and checks
//  what happened: pulls the orb, slides the session length (slowly, flicked, past the last drop,
//  and folded), drags the volume on past its end, and holds the ✕ (held, let go too soon and
//  clicked), on a bench that holds the four controls where it knows they are; then, on the app's
//  own session screen, holds its ✕ and presses Escape twice. It saves the window at each step as a
//  PNG. Compiled together with the app's sources, like Snapshots:
//
//    swiftc -parse-as-library -o drive macos-app/BreatheFree/{Core,Audio,Models,Views}/*.swift \
//      macos-app/Drive/Drive.swift && ./drive <output folder>
//
//  The events are posted to the app's own event queue, so it needs no permissions; but it needs
//  a screen, as GitHub's macOS runners have.
//  Exits with 1 if any check fails, and 2 if it doesn't finish in three minutes.
//

import AppKit
import QuartzCore
import SwiftUI

/// The window as the app has it, with the sky held at half past noon on 7 October 2026.
private struct Root: View {
    @ObservedObject var model: SessionModel
    let look: DayLook

    var body: some View {
        ZStack {
            SkyView(sky: look.sky)
            switch model.screen {
            case .home:
                HomeView(model: model)
            case .session:
                if let session = model.session {
                    SessionView(model: model, session: session)
                }
            case .done:
                DoneView(model: model)
            }
        }
        .environment(\.ink, Ink.matching(look))
    }
}

@MainActor
private final class Driver {
    let folder: URL
    let model = SessionModel()
    let bench = BenchState()
    let look: DayLook
    let window: NSWindow
    private(set) var failed = 0
    private var shots = 0

    init(folder: String) {
        self.folder = URL(fileURLWithPath: folder)
        // No sound: there may be no output on the machine, and none is needed.
        model.soundMode = .silent
        model.voiceOn = false
        model.focusOn = false
        model.cycles = 6
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 12, minute: 30))!
        look = DaySky.look(at: noon, in: zone)
        window = NSWindow(contentRect: NSRect(x: 40, y: 40, width: 960, height: 560),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Breathe Free"
        window.contentView = NSHostingView(rootView: Bench(state: bench, look: look))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Checks

    func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        if !ok { failed += 1 }
    }

    /// A check made by comparing pictures of the window, reported but not counted: on a busy
    /// machine a picture can be a frame or more behind what has happened. What these show is also
    /// checked in GesturesTests and drawn by Snapshots.
    func note(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "note  \(what) (from pictures, which can lag here)")
    }

    func wait(_ seconds: Double) async {
        guard seconds > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    // MARK: The mouse and keys

    private func mouse(_ type: NSEvent.EventType, _ p: NSPoint, in w: NSWindow) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                         clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
        // Into the app's own queue, as the mouse's events arrive, so they are taken in turn by
        // the event loop like any others.
        NSApp.postEvent(e, atStart: false)
    }

    func down(_ p: NSPoint, in w: NSWindow? = nil) { mouse(.leftMouseDown, p, in: w ?? window) }
    func up(_ p: NSPoint, in w: NSWindow? = nil) { mouse(.leftMouseUp, p, in: w ?? window) }

    /// Moves the held pointer from `a` by `by`, in `moves` even steps `every` seconds apart.
    @discardableResult
    func move(from a: NSPoint, by: NSPoint, moves: Int, every: Double, in w: NSWindow? = nil) async -> NSPoint {
        var p = a
        for i in 1...moves {
            p = NSPoint(x: a.x + by.x * Double(i) / Double(moves), y: a.y + by.y * Double(i) / Double(moves))
            mouse(.leftMouseDragged, p, in: w ?? window)
            await wait(every)
        }
        return p
    }

    func click(_ p: NSPoint, in w: NSWindow? = nil) async {
        down(p, in: w)
        await wait(0.06)
        up(p, in: w)
    }

    func escape() {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: window.windowNumber, context: nil,
                                        characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                        isARepeat: false, keyCode: 53) {
                NSApp.sendEvent(e)
            }
        }
    }

    // MARK: Pictures

    private func picture(of w: NSWindow) -> NSBitmapImageRep? {
        guard let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @discardableResult
    func save(_ name: String, _ w: NSWindow? = nil) -> NSBitmapImageRep? {
        guard let rep = picture(of: w ?? window), let png = rep.representation(using: .png, properties: [:]) else {
            print("      could not picture \(name)")
            return nil
        }
        shots += 1
        let url = folder.appendingPathComponent(String(format: "%02d-%@.png", shots, name))
        try? png.write(to: url)
        return rep
    }

    /// How different two pictures of the window are round `p` (window coordinates), from 0 to 1.
    func difference(_ a: NSBitmapImageRep?, _ b: NSBitmapImageRep?, around p: NSPoint, reach: Double) -> Double? {
        guard let a, let b, let bounds = window.contentView?.bounds, a.pixelsWide == b.pixelsWide else { return nil }
        let scale = Double(a.pixelsWide) / Double(bounds.width)
        var total = 0.0, n = 0.0
        for dy in stride(from: -reach, through: reach, by: 4) {
            for dx in stride(from: -reach, through: reach, by: 4) {
                // Bitmaps count rows from the top; the window, from the bottom.
                let x = Int((p.x + dx) * scale), y = Int((Double(bounds.height) - p.y - dy) * scale)
                guard x >= 0, y >= 0, x < a.pixelsWide, y < a.pixelsHigh,
                      let ca = a.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let cb = b.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                total += (abs(ca.redComponent - cb.redComponent) + abs(ca.greenComponent - cb.greenComponent)
                          + abs(ca.blueComponent - cb.blueComponent)) / 3
                n += 1
            }
        }
        return n > 0 ? total / n : nil
    }

    func centre(_ r: NSRect) -> NSPoint { NSPoint(x: r.midX, y: r.midY) }

    // MARK: The run

    /// Window coordinates (from the bottom) for a point measured from the top-left, as the views lay out.
    func at(_ x: Double, _ yFromTop: Double) -> NSPoint {
        NSPoint(x: x, y: Double(window.contentView?.bounds.height ?? 0) - yFromTop)
    }

    func run() async -> Bool {
        await wait(1.5)
        save("bench")

        // The orb: pulled down and to the right, then let go.
        // How often this machine draws, over a second.
        let frames0 = bench.frames, framesAt = CACurrentMediaTime()
        await wait(1)
        let fps = Double(bench.frames - frames0) / (CACurrentMediaTime() - framesAt)
        print(String(format: "      this machine draws %.0f frames a second", fps))
        // A step a frame at least, so no move is lost in another.
        let frame = max(0.016, 1.2 / max(fps, 1))

        let orb = at(Bench.orb.x, Bench.orb.y)
        let rest = picture(of: window)
        down(orb)
        await wait(frame)
        let to = await move(from: orb, by: NSPoint(x: 120, y: -100), moves: 10, every: frame)
        await wait(0.1)
        let pulled = save("orb-pulled")
        // Where the orb was drawn while pulled: about 27 points down and to the right of its place.
        let spot = NSPoint(x: orb.x + 21, y: orb.y - 17)
        await wait(0.1)
        up(to)
        await wait(0.16)
        save("orb-let-go")
        await wait(1.5)
        let after = picture(of: window)
        await wait(1.5)
        let home = picture(of: window)
        if let moved = difference(rest, pulled, around: orb, reach: 50),
           let left = difference(pulled, after, around: spot, reach: 20),
           let back = difference(rest, home, around: orb, reach: 50) {
            check(moved > 0.02, String(format: "the orb follows the pointer (%.3f)", moved))
            note(left > 0.02, String(format: "let go, it leaves where it was pulled to (%.3f)", left))
            note(back < 0.01, String(format: "and comes to rest where it was (%.3f)", back))
        } else {
            check(false, "pictures of the orb")
        }
        check(bench.cycles == 6 && !bench.open && bench.ended == 0, "pulling the orb presses nothing else")

        // The session length: a click opens it, and a slide picks where it is let go.
        let step = 54.0
        func drop(_ cycles: Int) -> NSPoint {
            let i = Double(SessionPlan.cycleChoices.firstIndex(of: cycles) ?? 0)
            let n = Double(SessionPlan.cycleChoices.count)
            return at(Bench.picker.x + (i - (n - 1) / 2) * step, Bench.picker.y)
        }
        let middle = at(Bench.picker.x, Bench.picker.y)
        func open() async {
            await click(middle)
            await wait(0.8)
        }
        await open()
        check(bench.open, "a click opens the session length")
        down(drop(6))
        await wait(0.04)
        var p = await move(from: drop(6), by: NSPoint(x: 2.2 * step, y: 0), moves: 12, every: 0.04)
        save("slide-over-20")
        await wait(0.3)
        up(p)
        await wait(1.0)
        check(bench.cycles == 20 && !bench.open, "slid slowly from 6 by 2.2 drops, it picks 20, and folds (\(bench.cycles))")
        save("slide-picked-20")

        bench.cycles = 6
        await wait(0.3)
        await open()
        // Fast: 1.6 drops in a tenth of a second, let go straight after the last move. A flick
        // needs a move at least every 40 ms (Gestures.swift, VelocityTracker); a machine that
        // draws more slowly than that can't show one.
        down(drop(6))
        await wait(0.016)
        let flickAt = CACurrentMediaTime()
        p = await move(from: drop(6), by: NSPoint(x: 1.6 * step, y: 0), moves: 6, every: 0.016)
        let apart = (CACurrentMediaTime() - flickAt) / 6
        up(p)
        await wait(1.0)
        if apart < 0.035 {
            check(bench.cycles == 36, "flicked from 6, it carries on to 36 (\(bench.cycles))")
        } else {
            print(String(format: "skip  flicked from 6: the moves went out %.0f ms apart here, and a flick needs them under 40 (\(bench.cycles))", apart * 1000))
        }

        await open()
        down(drop(36))
        await wait(0.04)
        p = await move(from: drop(36), by: NSPoint(x: 4 * step, y: 0), moves: 16, every: 0.04)
        save("slide-held-back-past-50")
        await wait(0.3)
        up(p)
        await wait(1.0)
        check(bench.cycles == 50, "slid past the last drop, it holds back and picks 50 (\(bench.cycles))")

        // Folded, a short slide that stays on the drop only opens it, as Android's test (10 dp).
        down(middle)
        await wait(0.03)
        p = await move(from: middle, by: NSPoint(x: 10, y: 0), moves: 5, every: 0.016)
        up(p)
        await wait(0.8)
        check(bench.cycles == 50 && bench.open, "folded, a slide only opens it")
        await click(drop(6))
        await wait(0.8)
        check(bench.cycles == 6 && !bench.open, "open, a click still picks (\(bench.cycles))")

        // The volume: dragged on past its end, it gives, and it is full.
        bench.volume = 0.5
        await wait(0.2)
        let knob = at(Bench.slider.x, Bench.slider.y)
        down(knob)
        await wait(frame)
        p = await move(from: knob, by: NSPoint(x: Bench.sliderWidth / 2 + 60, y: 0), moves: 12, every: frame)
        await wait(0.1)
        let stretched = save("volume-stretched")
        await wait(0.05)
        up(p)
        await wait(1.2)
        let settled = picture(of: window)
        check(bench.volume == 1, "dragged on past its end, the volume is full (\(bench.volume))")
        let end = at(Bench.slider.x + Bench.sliderWidth / 2 - 9, Bench.slider.y)
        if let gave = difference(stretched, settled, around: end, reach: 14) {
            note(gave > 0.01, String(format: "and the slider gives, then springs back (%.3f)", gave))
        }

        // The ✕: held for a second it ends; let go too soon, or clicked, it doesn't.
        let x = at(Bench.cross.x, Bench.cross.y)
        down(x)
        await wait(0.5)
        save("cross-half-held")
        check(bench.ended == 0, "half way through the hold, nothing has ended")
        await wait(0.65)
        check(bench.ended == 1, "held for a second, the ✕ ends the session")
        up(x)
        await wait(4.5)
        down(x)
        await wait(0.8)
        up(x)
        await wait(1.0)
        save("cross-let-go")
        check(bench.ended == 1, "let go too soon, nothing ends")
        for _ in 0..<2 {
            await click(x)
            await wait(0.4)
        }
        check(bench.ended == 1, "clicks only open it")
        down(x)
        await wait(1.3)
        up(x)
        await wait(0.5)
        check(bench.ended == 2, "a hold after that ends it")

        // The app's own session screen: the ✕ in its top bar, held, and Escape twice.
        await wait(4.5)
        window.contentView = NSHostingView(rootView: Root(model: model, look: look))
        model.begin()
        await wait(1.5)
        save("session")
        let w = Double(window.contentView?.bounds.width ?? 0)
        // The top bar: 16 in from the right and 14 down, buttons 40 across, 10 apart.
        let cross = at(w - 16 - 20, 14 + 20)
        down(cross)
        await wait(0.5)
        save("session-cross-half-held")
        check(model.screen == .session, "in a session, half way through the hold it carries on")
        await wait(0.65)
        check(model.screen == .home, "held for a second, the session's ✕ ends it")
        up(cross)
        await wait(0.8)
        model.begin()
        await wait(1.5)
        escape()
        await wait(0.5)
        check(model.screen == .session, "Escape once only opens End session")
        escape()
        await wait(0.5)
        check(model.screen == .home, "Escape twice ends the session")
        save("home-again")
        return failed == 0
    }
}

/// What the bench's controls have done.
@MainActor
final class BenchState: ObservableObject {
    @Published var cycles = 6
    @Published var open = false
    @Published var volume = 0.5
    @Published var ended = 0
    /// Frames drawn so far, to know how often this machine draws.
    var frames = 0
}

/// The four controls on their own, where the drive knows they are (from the top-left), on the sky.
private struct Bench: View {
    @ObservedObject var state: BenchState
    let look: DayLook

    static let orb = CGPoint(x: 160, y: 160)
    static let picker = CGPoint(x: 500, y: 160)
    static let cross = CGPoint(x: 840, y: 160)
    static let slider = CGPoint(x: 500, y: 340)
    static let sliderWidth = 180.0

    var body: some View {
        ZStack {
            // The sky without its drifting clouds, so a picture changes only where a control does.
            Canvas { context, size in SceneDrawing.sky(&context, size: size, palette: look.sky) }
            // Counts the frames, as everything here is drawn once a frame.
            TimelineView(.animation) { timeline in
                Color.clear.task(id: timeline.date) { state.frames += 1 }
            }
            // Holding still rather than breathing, so a picture of it changes only as it is pulled.
            AmbientOrb(colors: Ink.matching(look).orb, sun: Ink.matching(look).sun, depth: 0)
                .frame(width: 112, height: 112)
                .position(Self.orb)
            CyclePicker(choices: SessionPlan.cycleChoices, selection: $state.cycles, open: $state.open,
                        describe: { "\($0) cycles" })
                .position(Self.picker)
            EndSessionButton(end: { state.ended += 1 })
                .position(Self.cross)
            GiveSlider(value: $state.volume, label: "Volume")
                .frame(width: Self.sliderWidth)
                .position(Self.slider)
        }
        .environment(\.ink, Ink.matching(look))
    }
}

@main
struct Drive {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let folder = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
        DispatchQueue.main.asyncAfter(deadline: .now() + 180) {
            print("Timed out.")
            exit(2)
        }
        Task { @MainActor in
            let driver = Driver(folder: folder)
            let ok = await driver.run()
            print(ok ? "All checks passed." : "\(driver.failed) check(s) failed.")
            exit(ok ? 0 : 1)
        }
        app.run()
    }
}

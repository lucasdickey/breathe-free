//
//  Drive.swift
//
//  Opens the app's screens in a real window and works them with the mouse and keys as someone
//  would, then checks what happened: pulls the orb on the home screen, slides the session length
//  (slowly, flicked, past the last drop, and folded), drags the volume on past its end, and holds
//  the ✕ to end a session (held, let go too soon, clicked, and Escape twice). It saves the window
//  at each step as a PNG. Compiled together with the app's sources, like Snapshots:
//
//    swiftc -parse-as-library -o drive macos-app/BreatheFree/{Core,Audio,Models,Views}/*.swift \
//      macos-app/Drive/Drive.swift && ./drive <output folder>
//
//  It finds the controls by what VoiceOver reads for them, and sends the events to the app
//  itself, so it needs no permissions; but it needs a screen, as GitHub's macOS runners have.
//  Exits with 1 if any check fails, and 2 if it doesn't finish in three minutes.
//

import AppKit
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
        window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 960, height: 760),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Breathe Free"
        window.contentView = NSHostingView(rootView: Root(model: model, look: DaySky.look(at: noon, in: zone)))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Checks

    func check(_ ok: Bool, _ what: String) {
        print(ok ? "ok    \(what)" : "FAIL  \(what)")
        if !ok { failed += 1 }
    }

    func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
    }

    // MARK: Finding things, as VoiceOver does

    /// An element's attribute, through the typed accessibility protocol where the element has it,
    /// and the older attribute interface (which VoiceOver goes through) where it doesn't.
    private func attribute(_ o: AnyObject, _ name: NSAccessibility.Attribute) -> Any? {
        if let e = o as? NSAccessibilityProtocol {
            switch name {
            case .children: return e.accessibilityChildren()
            case .description: return e.accessibilityLabel()
            case .title: return e.accessibilityTitle()
            case .value: return e.accessibilityValue()
            case .role: return e.accessibilityRole()
            default: break
            }
        }
        return (o as? NSObject)?.accessibilityAttributeValue(name)
    }

    private func children(_ o: AnyObject) -> [AnyObject] {
        ((attribute(o, .children) as? [Any]) ?? []).map { $0 as AnyObject }
    }

    private func role(_ o: AnyObject) -> NSAccessibility.Role? {
        if let r = attribute(o, .role) as? NSAccessibility.Role { return r }
        return (attribute(o, .role) as? String).map { NSAccessibility.Role(rawValue: $0) }
    }

    /// Where an element is on the screen.
    private func frame(_ o: AnyObject) -> NSRect? {
        if let e = o as? NSAccessibilityProtocol { return e.accessibilityFrame() }
        if let e = o as? NSAccessibilityElementProtocol { return e.accessibilityFrame() }
        return (attribute(o, NSAccessibility.Attribute(rawValue: "AXFrame")) as? NSValue)?.rectValue
    }

    private func words(_ o: AnyObject) -> String {
        [attribute(o, .description), attribute(o, .title), attribute(o, .value)]
            .compactMap { $0.map { "\($0)" } }
            .filter { !$0.isEmpty }
            .joined(separator: " | ")
    }

    private func all(in w: NSWindow) -> [AnyObject] {
        guard let root = w.contentView else { return [] }
        var out: [AnyObject] = []
        func walk(_ o: AnyObject, _ depth: Int) {
            out.append(o)
            guard depth < 60 else { return }
            for k in children(o) { walk(k, depth + 1) }
        }
        walk(root, 0)
        return out
    }

    /// Where the first control whose words pass `match` is, in `w`'s own coordinates.
    func find(_ what: String, in w: NSWindow? = nil, role: NSAccessibility.Role? = nil,
              _ match: (String) -> Bool) -> NSRect? {
        let w = w ?? window
        for o in all(in: w) {
            if let role, self.role(o) != role { continue }
            guard match(words(o)) else { continue }
            guard let rect = frame(o), rect.width > 0 else { continue }
            return w.convertFromScreen(rect)
        }
        print("      could not find \(what); the window holds:")
        for o in all(in: w) where !words(o).isEmpty {
            print("        \(self.role(o)?.rawValue ?? "?"): \(words(o))")
        }
        return nil
    }

    // MARK: The mouse and keys

    private func mouse(_ type: NSEvent.EventType, _ p: NSPoint, in w: NSWindow) {
        guard let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: [],
                                         timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: w.windowNumber, context: nil, eventNumber: 0,
                                         clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1) else { return }
        NSApp.sendEvent(e)
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

    func run() async -> Bool {
        await wait(1.5)
        save("home")

        // The orb, above the title: pulled down and to the right, then let go.
        guard let title = find("the title", { $0.contains("Breathe Free") }) else { return false }
        let orb = NSPoint(x: title.midX, y: title.maxY + 12 + 56)
        let rest = picture(of: window)
        down(orb)
        await wait(0.05)
        let to = await move(from: orb, by: NSPoint(x: 120, y: -100), moves: 10, every: 0.016)
        let pulled = save("orb-pulled")
        up(to)
        await wait(0.16)
        save("orb-let-go")
        await wait(1.5)
        let home = picture(of: window)
        check(model.screen == .home && model.cycles == 6, "pulling the orb presses nothing else")
        if let moved = difference(rest, pulled, around: orb, reach: 60),
           let back = difference(pulled, home, around: orb, reach: 60) {
            check(moved > 0.02, String(format: "the orb follows the pointer (%.3f)", moved))
            check(back > 0.02, String(format: "let go, it goes home (%.3f)", back))
        } else {
            print("      (could not compare pictures of the orb)")
        }

        // The session length: a click opens it, and a slide picks where it is let go.
        let step = 54.0
        func open(_ cycles: Int) async -> Bool {
            guard let drop = find("session length", { $0.hasPrefix("Session length: \(cycles) cycles") }) else { return false }
            await click(centre(drop))
            await wait(0.8)
            return find("the open row", { $0.hasPrefix("10 cycles,") }) != nil
        }
        func drop(_ cycles: Int) -> NSPoint? {
            find("the \(cycles) drop", { $0.hasPrefix("\(cycles) cycles,") }).map(centre)
        }
        check(await open(6), "a click opens the session length")
        if let from = drop(6) {
            down(from)
            await wait(0.04)
            let at = await move(from: from, by: NSPoint(x: 2.2 * step, y: 0), moves: 12, every: 0.04)
            save("slide-over-20")
            await wait(0.3)
            up(at)
            await wait(1.0)
            check(model.cycles == 20, "slid slowly from 6 by 2.2 drops, it picks 20 (\(model.cycles))")
            save("slide-picked-20")
        }
        model.cycles = 6
        await wait(0.3)
        if await open(6), let from = drop(6) {
            // Fast: 1.6 drops in a tenth of a second, let go mid-move.
            down(from)
            await wait(0.016)
            let at = await move(from: from, by: NSPoint(x: 1.6 * step, y: 0), moves: 6, every: 0.016)
            up(at)
            await wait(1.0)
            check(model.cycles == 36, "flicked from 6, it carries on to 36 (\(model.cycles))")
        } else {
            check(false, "the session length opens again")
        }
        if await open(36), let from = drop(36) {
            down(from)
            await wait(0.04)
            let at = await move(from: from, by: NSPoint(x: 4 * step, y: 0), moves: 16, every: 0.04)
            save("slide-held-back-past-50")
            await wait(0.3)
            up(at)
            await wait(1.0)
            check(model.cycles == 50, "slid past the last drop, it holds back and picks 50 (\(model.cycles))")
        } else {
            check(false, "the session length opens from 36")
        }
        if let folded = find("session length", { $0.hasPrefix("Session length: 50 cycles") }) {
            // Folded, a slide only opens it.
            let p = centre(folded)
            down(p)
            await wait(0.03)
            let at = await move(from: p, by: NSPoint(x: 30, y: 0), moves: 5, every: 0.016)
            up(at)
            await wait(0.8)
            check(model.cycles == 50 && find("the open row", { $0.hasPrefix("10 cycles,") }) != nil,
                  "folded, a slide only opens the session length")
            if let six = drop(6) {
                await click(six)
                await wait(0.8)
                check(model.cycles == 6, "open, a click still picks (\(model.cycles))")
            }
        }

        // A session: the volume gives past its end, and the ✕ ends it when held.
        model.cycles = 2
        await wait(0.3)
        guard let begin = find("Begin", { $0.contains("Begin") }) else { return false }
        await click(centre(begin))
        await wait(1.5)
        check(model.screen == .session, "Begin starts a session")
        if let volume = find("the volume button", role: .button, { $0.contains("Volume") }) {
            await click(centre(volume))
            await wait(0.8)
            if let popover = NSApp.windows.first(where: { $0 !== window && $0.isVisible }),
               let slider = find("the volume slider", in: popover, role: .slider, { _ in true }) {
                model.volume = 0.5
                await wait(0.2)
                let from = centre(slider)
                down(from, in: popover)
                await wait(0.03)
                let at = await move(from: from, by: NSPoint(x: slider.width / 2 + 60, y: 0), moves: 12,
                                    every: 0.016, in: popover)
                save("volume-stretched", popover)
                up(at, in: popover)
                await wait(0.6)
                save("volume-back", popover)
                check(model.volume == 1, "dragged on past its end, the volume is full (\(model.volume))")
            } else {
                check(false, "the volume opens with its slider")
            }
            // Away from the popover, to close it.
            await click(NSPoint(x: 80, y: 80))
            await wait(0.6)
        }

        func cross() -> NSPoint? { find("the ✕", { $0.hasPrefix("End session") }).map(centre) }
        if let x = cross() {
            down(x)
            await wait(0.5)
            save("cross-half-held")
            check(model.screen == .session, "half way through the hold, the session carries on")
            await wait(0.65)
            check(model.screen == .home, "held for a second, the ✕ ends the session")
            up(x)
            await wait(0.8)
        }
        if let begin = find("Begin", { $0.contains("Begin") }) {
            await click(centre(begin))
            await wait(1.5)
        }
        if model.screen == .session, let x = cross() {
            down(x)
            await wait(0.8)
            up(x)
            await wait(1.0)
            save("cross-let-go")
            check(model.screen == .session, "let go too soon, the session carries on")
            for _ in 0..<2 {
                if let x = cross() { await click(x) }
                await wait(0.4)
            }
            check(model.screen == .session, "clicks only open it")
            if let x = cross() {
                down(x)
                await wait(1.3)
                up(x)
            }
            await wait(0.5)
            check(model.screen == .home, "a hold after that ends it")
        } else {
            check(false, "a second session starts")
        }
        if let begin = find("Begin", { $0.contains("Begin") }) {
            await click(centre(begin))
            await wait(1.5)
            escape()
            await wait(0.5)
            check(model.screen == .session, "Escape once only opens End session")
            escape()
            await wait(0.5)
            check(model.screen == .home, "Escape twice ends the session")
        }
        save("home-again")
        return failed == 0
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

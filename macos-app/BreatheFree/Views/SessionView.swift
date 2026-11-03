//
//  SessionView.swift
//  BreatheFree
//
//  The session: everything on screen is computed afresh each frame from the session
//  clock, so nothing can lag behind or drift from the sound.
//

import AppKit
import SwiftUI
import QuartzCore

struct SessionView: View {
    @ObservedObject var model: SessionModel
    let session: ActiveSession
    /// Starts with End session open, as the screen renderer shows it.
    let endOpen: Bool
    @State private var showVolume = false
    /// Whether End session is open, waiting for its second click.
    @State private var ending: Bool
    @Environment(\.ink) private var ink
    // With Reduce Motion on, the words cross in place instead of on the wind, and focus mode's
    // controls fade in place instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Focus mode: the top bar and the count keep out of sight until the mouse moves, a click or
    // a key; then they stay a few seconds from the last. They stay while the session is paused
    // or End session or the volume is open, and for a few seconds after. With VoiceOver on they
    // always stay, as it can't find what isn't there.
    /// Each stir of the mouse, click or key press.
    @State private var stirs = 0
    @State private var stirredLately: Bool
    @State private var events: Any?
    @StateObject private var voiceOver = VoiceOverWatch()

    /// A frame drawn now reaches the screen about one refresh later; aim the picture there.
    static let displayLead = 1.0 / 60.0

    /// How long focus mode's controls stay in sight after the last stir.
    static let focusShown = Duration.seconds(3)

    /// `controlsShown` false starts focus mode's controls out of sight, as the screen renderer shows them.
    init(model: SessionModel, session: ActiveSession, endOpen: Bool = false, controlsShown: Bool = true) {
        self.model = model
        self.session = session
        self.endOpen = endOpen
        _ending = State(initialValue: endOpen)
        _stirredLately = State(initialValue: controlsShown)
    }

    private var tucked: Bool {
        model.focusOn && !voiceOver.on && !stirredLately && !session.isPaused && !ending && !showVolume
    }

    var body: some View {
        let tucked = tucked
        GeometryReader { geo in
            let g = SceneGeometry.of(geo.size)
            let promptY = g.cy + g.half + 58
            // The clear sky under the words, down to just above the cycle count, for the specks on the low road.
            let room = max(0, geo.size.height - 100 - promptY)
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
                            .position(x: g.cx, y: promptY)
                        Text("Press Space to carry on")
                            .font(.system(size: 15))
                            .foregroundColor(ink.soft.color)
                            .position(x: g.cx, y: g.cy + g.half + 96)
                    } else {
                        // The words, worked out from the session clock like everything else.
                        let words = session.plan.prompt(at: t)
                        if reduceMotion {
                            // The words before fade out as the new ones fade in, each centred on its own.
                            Text(words.previous)
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(ink.deep.color)
                                .opacity(1 - words.fade)
                                .position(x: g.cx, y: promptY)
                                .accessibilityHidden(true)
                            Text(words.text)
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(ink.deep.color)
                                .opacity(words.fade)
                                .position(x: g.cx, y: promptY)
                                .accessibilityAddTraits(.updatesFrequently)
                        } else {
                            // Specks of ink on the wind: in from the left, off to the right as the next words come.
                            Canvas { context, size in
                                WindWords.shared.draw(&context, gust: session.plan.gust(at: t), cx: g.cx, cy: promptY,
                                                      reach: size.width, room: room, level: frame.level, t: t,
                                                      color: ink.deep)
                            }
                            .accessibilityHidden(true)
                            // What the specks spell, for VoiceOver: the words themselves, where they are drawn, in no colour.
                            Text(words.text)
                                .font(.system(size: 30, weight: .light))
                                .foregroundColor(.clear)
                                .position(x: g.cx, y: promptY)
                                .accessibilityAddTraits(.updatesFrequently)
                        }

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
                    .modifier(Tucked(away: tucked, up: false, reduceMotion: reduceMotion))

                    Text(clockText(Int((frame.remaining - 1e-9).rounded(.up))))
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundColor(ink.deep.color)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 22)
                        .accessibilityLabel("\(spokenClock(Int((frame.remaining - 1e-9).rounded(.up)))) left")
                        .modifier(Tucked(away: tucked, up: true, reduceMotion: reduceMotion))
                }
                .animation(.easeInOut(duration: 0.35), value: paused)
            }
            topBar
                .modifier(Tucked(away: tucked, up: true, reduceMotion: reduceMotion))
        }
        // Moving the mouse over the window, a click or a key brings focus mode's controls back,
        // and goes on to whatever it was for.
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase, model.focusOn { stirs += 1 }
        }
        .onAppear {
            events = NSEvent.addLocalMonitorForEvents(
                matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
            ) { event in
                if model.focusOn { stirs += 1 }
                return event
            }
        }
        .onDisappear {
            if let events { NSEvent.removeMonitor(events) }
        }
        .task(id: Stir(count: stirs, paused: session.isPaused, ending: ending, volume: showVolume)) {
            stirredLately = true
            try? await Task.sleep(for: Self.focusShown)
            if !Task.isCancelled { stirredLately = false }
        }
        // As a video does, the pointer keeps out of sight with them until the mouse moves.
        .onChange(of: tucked) { away in
            if away && NSApp.isActive { NSCursor.setHiddenUntilMouseMoves(true) }
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
            RoundIconButton(systemImage: volumeSymbol, label: "Volume") { showVolume.toggle() }
                .popover(isPresented: $showVolume, arrowEdge: .bottom) {
                    volumePanel.padding(16)
                }
            EndSessionButton(open: endOpen, end: model.endSession, opened: { ending = $0 })
        }
        .padding(.top, 14)
        .padding(.horizontal, 16)
    }

    /// How loud: one slider, or with the voice on, the tone's and the voice's, each named.
    @ViewBuilder private var volumePanel: some View {
        if model.voiceOn {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Tone")
                    Slider(value: $model.volume, in: 0...1).frame(width: 180)
                        .accessibilityLabel("Tone volume")
                }
                GridRow {
                    Text("Voice")
                    Slider(value: $model.voiceVolume, in: 0...1).frame(width: 180)
                        .accessibilityLabel("Voice volume")
                }
            }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                Slider(value: $model.volume, in: 0...1).frame(width: 180)
                Image(systemName: "speaker.wave.3.fill")
            }
        }
    }

    /// The volume button shows how loud it is, as the menu bar's speaker does: the louder of
    /// the two with the voice on.
    private var volumeSymbol: String {
        switch model.voiceOn ? max(model.volume, model.voiceVolume) : model.volume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
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

/// What starts focus mode's few seconds in sight again: a stir, or pausing, ending or the volume
/// opening or closing.
private struct Stir: Equatable {
    let count: Int
    let paused: Bool
    let ending: Bool
    let volume: Bool
}

/// Focus mode's controls, slid off to the nearest edge (`up`, or down) and faded while `away`, or
/// with Reduce Motion only faded; out of reach of the pointer and VoiceOver while they're gone.
private struct Tucked: ViewModifier {
    let away: Bool
    let up: Bool
    let reduceMotion: Bool

    /// Far enough to take the top bar or the count past the window's edge.
    private static let distance = 64.0
    /// As Android's: quick to start, slow to settle; out in 600 ms and back in 300.
    private static func easing(_ seconds: Double) -> Animation { .timingCurve(0.4, 0, 0.2, 1, duration: seconds) }

    func body(content: Content) -> some View {
        content
            .offset(y: away && !reduceMotion ? (up ? -1 : 1) * Self.distance : 0)
            .opacity(away ? 0 : 1)
            .animation(Self.easing(away ? 0.6 : 0.3), value: away)
            .allowsHitTesting(!away)
            .accessibilityHidden(away)
    }
}

/// Whether VoiceOver is running, kept up to date.
private final class VoiceOverWatch: ObservableObject {
    @Published private(set) var on = NSWorkspace.shared.isVoiceOverEnabled
    private var watch: NSKeyValueObservation?

    init() {
        watch = NSWorkspace.shared.observe(\.isVoiceOverEnabled) { [weak self] workspace, _ in
            DispatchQueue.main.async { self?.on = workspace.isVoiceOverEnabled }
        }
    }
}

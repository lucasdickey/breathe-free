# Breathe Free for macOS

A native SwiftUI app for box breathing: in for four, hold for four, out for four,
hold for four, with an eight-second settle at the start.

## What you see and hear

- **The box.** A dot travels around a rounded square, one side per phase. It rises
  up the left side as you breathe in, crosses the top while you hold, falls down the
  right as you breathe out and returns along the bottom. Its height is always the
  breath itself.
- **The orb** in the middle grows and shrinks with the same curve, and a soft ring
  leaves it at each change of phase.
- **The sky** follows the time of day: night with stars, blue hour, sunrise, day,
  golden hour, sunset and dusk, timed from that day's sunrise and sunset (worked out
  from the date, so no location is needed; `Core/DaySky.swift`). Text and buttons turn
  light when the sky is dark. During a session it brightens a little as you fill up.
  The clouds are drawn procedurally, so they drift and slowly change shape.
- **The sound** is generated as it plays, not looped from a file:
  - a low D drone with two upper notes that change each cycle and bloom on the inhale,
  - soft filtered "air" that only moves while breath moves,
  - a gentle bell exactly on each change: A for breathe in, D for breathe out,
    quieter high and low notes for the holds.
- **Sound modes**: Ambient, Bells only, or Silent, plus a volume slider. The speaker
  button in a session switches mode without stopping.
- The Force Touch trackpad taps at each change if a finger is resting on it.

Keys: **Return** begins, **Escape** ends a session.

## How the timing stays exact

Everything comes from one clock. A session starts at a host time (`CACurrentMediaTime`)
and every frame works out the phase, countdown, orb size and dot position from
`now - start` (`Core/BreathTimeline.swift`). Nothing is counted in ticks, so nothing
can drift.

The sound is placed on the same clock. For each block it renders, Core Audio reports
when that block leaves for the device, and the output device reports the delay after
that (`presentationLatency`, which includes AirPods and other Bluetooth output).
`Audio/SessionAudio.swift` tells the synth the session time at which the block will
actually be heard; the synth (`Core/BreathSynth.swift`) nudges its own clock by at most
0.2% to follow, or re-aligns after a real gap such as switching outputs.

`Core/` is shared in design with the Android app: `BreathTimeline.swift` and
`BreathSynth.swift` are line-for-line ports of the Kotlin files, and a rendered session
is identical between the two at 16-bit resolution.

## Building

Requirements: macOS 13 or later, Xcode 15 or later.

```bash
open macos-app/BreatheFree.xcodeproj   # then Run (Cmd+R)
```

Pick your team (or "Sign to Run Locally") under Signing & Capabilities the first time.

From the command line, without signing:

```bash
xcodebuild -project macos-app/BreatheFree.xcodeproj -target BreatheFree \
  -configuration Release CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
open macos-app/build/Release/BreatheFree.app
```

Every push that touches the app also builds it on GitHub Actions ("Build apps"), and the
zipped app is attached to the run as `BreatheFree-macOS`. It is ad-hoc signed, so the
first launch needs right-click → Open.

## Tests

The timing and sound code builds on its own with Swift Package Manager, on macOS or
Linux:

```bash
swift test --package-path macos-app
```

The tests check phase boundaries and countdowns, that every bell starts on the exact
sample of its phase change, that the sound follows a device clock running fast, that
the air layer is silent during holds, and that output never clips.

## Project layout

```
macos-app/
├── BreatheFree.xcodeproj
├── Package.swift                 # builds Core/ alone for tests
├── Tests/BreatheCoreTests/
└── BreatheFree/
    ├── BreatheFreeApp.swift      # window, menus
    ├── ContentView.swift         # sky behind; home, session or finish in front
    ├── Core/
    │   ├── BreathTimeline.swift  # the session laid out in time
    │   └── BreathSynth.swift     # the generated sound
    ├── Audio/SessionAudio.swift  # AVAudioEngine, aligned to the session clock
    ├── Models/
    │   ├── SessionModel.swift    # saved choices, screens, session start and end
    │   └── HapticManager.swift   # trackpad taps
    └── Views/
        ├── SceneDrawing.swift    # colours, clouds, orb, box
        ├── SkyView.swift
        ├── HomeView.swift
        ├── SessionView.swift
        ├── DoneView.swift
        └── Controls.swift
```

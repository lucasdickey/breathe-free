# Breathe Free 🧘‍♀️

A calm guide for box breathing: in for four, hold for four, out for four, hold for four.

| App | Folder | Built with |
|-----|--------|------------|
| macOS | [`macos-app`](macos-app/README.md) | Swift, SwiftUI, AVAudioEngine |
| Android | [`android-app`](android-app/README.md) | Kotlin, Jetpack Compose, AudioTrack |
| Web | [`breathing-app`](breathing-app/README.md) | Next.js, Web Audio |

`expo-app` is the earlier React Native build for Android, kept for reference; the
native Android app replaces it.

## How the apps keep time and make sound

All three are built the same way, so they sound and keep time alike.

**One clock.** A session is laid out on a single time axis: an 8 second settle, then
16 second cycles. Every frame works out the phase, the countdown and the size of the
orb (and, in the native apps, the dot on the box) from elapsed time alone
(`BreathTimeline` in the native apps, `computeFrame` in the web app's
`useBreathingSession`). Nothing counts ticks, so nothing drifts, and a frame that
arrives late simply shows the right moment.

**Generated sound.** Instead of a looped recording stretched to fit, the sound is
computed sample by sample from the same breath curve the picture uses (`BreathSynth`):

- a low D drone with two upper notes from the D major pentatonic scale, changing each
  cycle and blooming as the lungs fill;
- soft filtered "air" that moves only while breath moves, rising on the inhale and
  falling on the exhale;
- a soft bell on every change: A for breathe in, D for breathe out, quiet high and low
  notes for the holds, and a closing chord.

It stays below about 1 kHz, nothing beats faster than once every few seconds, and the
levels peak around -4 dBFS, so it is easy to listen to for a long session.

**Sound placed on the clock.** Each platform reports when a block of audio will actually
come out of the speaker or headphones, including Bluetooth delay. The synth is told the
session time of that moment and bends its own clock to match, so a bell sounds as the
words change on screen. On the web the synth runs as an AudioWorklet
(`breathing-app/public/worklets/breath-synth.js`) on the AudioContext clock, and the
page draws the moment that is audible now (`getOutputTimestamp`), not the one being
rendered, which runs about 80 ms ahead in Chrome.

The Kotlin, Swift and JavaScript versions of `BreathSynth` are line-for-line ports of
each other. A rendered session is identical between Kotlin and Swift at 16-bit
resolution; the JavaScript one differs by at most the smallest 16-bit step on about
0.02% of samples (rounding in the browser's maths library).

## Adding a recorded voice (next step)

The synth already marks each cue (every phase change, the welcome and the closing) at
the exact sample it starts on: `onCue` in `BreathSynth`. Spoken prompts, for example
ElevenLabs recordings of "Breathe in", "Hold" and "Breathe out", will be mixed in at
those same samples, nudged a little early so the stressed word lands on the change.
They would become a fourth sound mode alongside Ambient, Bells and Silent.

## Builds

Pushing to GitHub runs "Build apps", which tests both apps and attaches a zipped
`BreatheFree.app` and `app-release.apk` to the run. The APK is signed with the app's
permanent key, so from 2.0.1 each version installs over the last; see
[Signing](android-app/README.md#signing).

## Web app quick start

```bash
cd breathing-app
npm install
npm run dev   # http://localhost:3000
```

See [ROADMAP.md](breathing-app/ROADMAP.md) for older plans.

## License

MIT License

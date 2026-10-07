# Breathe Free for Android

A native Kotlin and Jetpack Compose app for box breathing: in for four, hold for four,
out for four, hold for four, with an eight-second settle at the start. It replaces the
Expo build in `../expo-app`, whose audio was switched off.

The design matches the macOS app: the dot on the box rises and falls with the breath,
the orb grows and shrinks on the same curve, the dusk sky brightens as you fill up, and
the sound (a drone that blooms on the inhale, soft moving air, a bell on every change)
is generated as it plays. See `../macos-app/README.md` for the full description.

## How the timing stays exact

- `core/BreathTimeline.kt` turns elapsed time into everything on screen. The screen
  reads the frame clock every vsync, so nothing is counted in ticks and nothing drifts.
- `core/BreathSynth.kt` generates the sound sample by sample from the same session
  time and the same breath curve.
- `audio/SessionAudio.kt` writes the sound to an `AudioTrack` and asks Android when
  each block will actually be heard (`AudioTrack.getTimestamp`, which includes
  Bluetooth delay on phones that report it). The synth bends its clock to match, so
  bells land on the boundaries the screen shows.
- Haptic ticks fire from the frame loop, on the same clock.

## Install

Download `app-release.apk` (from the "Build apps" GitHub Actions run, or build it as
below), copy it to the phone and open it. Android will ask you to allow installs from
that app the first time.

If the old Expo build is installed, uninstall it first: both use the package name
`com.breathefree.app` but are signed with different keys.

Needs Android 8.0 or later.

## Build

Requirements: JDK 17 or later and the Android SDK (platform 37). Android Studio has
both.

```bash
cd android-app
./gradlew assembleRelease      # app/build/outputs/apk/release/app-release.apk
./gradlew testDebugUnitTest    # timeline, sound and audio-thread tests
```

Release builds are signed with the key in `keystore.properties` if that file exists:

```properties
storeFile=release.jks
storePassword=...
keyAlias=...
keyPassword=...
```

Otherwise they use the debug key, which is fine for installing on your own phone.
Keep using the same key from then on, or each new build will need the app uninstalled
first.

### Screenshots without a device

```bash
./gradlew testDebugUnitTest -Pscreenshots --tests '*ScreenshotTest*'
```

renders the real screens at chosen moments of a session (Robolectric) into
`app/build/screenshots/`.

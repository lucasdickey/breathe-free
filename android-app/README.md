# Breathe Free for Android

A native Kotlin and Jetpack Compose app for box breathing: in for four, hold for four,
out for four, hold for four, with an eight-second settle at the start. It replaces the
Expo build in `../expo-app`, whose audio was switched off.

The design matches the macOS app: the dot on the box rises and falls with the breath,
the orb grows and shrinks on the same curve, the sky follows the time of day while its
clouds drift on without a break, and
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

Download the APK from [one-off.dev/breathe-free](https://one-off.dev/breathe-free) (or
`app-release.apk` from a "Build apps" run on `main`), copy it to the phone and open it.
Android will ask you to allow installs from that app the first time.

If Breathe Free 2.0 or earlier is installed (the Expo build, or the first native build),
uninstall it first: those were signed with other keys, and Android won't install over an
app signed with a different key. From 2.0.1 on, every build is signed with the app's
permanent key (see [Signing](#signing)), so updates install over the top.

Needs Android 8.0 or later.

## Build

Requirements: JDK 17 or later and the Android SDK (platform 37). Android Studio has
both.

```bash
cd android-app
./gradlew assembleRelease      # app/build/outputs/apk/release/app-release.apk
./gradlew testDebugUnitTest    # timeline, sound and audio-thread tests
```

### Signing

From 2.0.1, release builds are signed with the app's permanent key:

- alias `breathe-free`, valid until 2054, certificate SHA-256
  `70:AD:F9:55:09:F7:7E:DC:47:A8:1B:0B:83:05:95:5F:78:4D:87:64:7F:81:BD:C7:3F:00:07:8D:40:E6:32:AE`
- not in this repository: GitHub holds it as two repository secrets,
  `ANDROID_KEYSTORE_BASE64` (the `.p12` key file as base64) and
  `ANDROID_KEYSTORE_PASSWORD`, and Lucas keeps the original.

"Build apps" writes the key from those secrets before building, and fails if the APK
comes out with any other certificate. Without the secrets it still builds, signed with a
throwaway key, and says so in a warning. So the APK to publish is the one from a run on
`main` with no such warning.

To sign a local build instead, describe the key in `keystore.properties` (ignored by git).
The key password is the same as the store password, since a `.p12` file has only one:

```properties
storeFile=/path/to/breathe-free-release.p12
storePassword=...
keyAlias=breathe-free
keyPassword=...
```

Without that file a local build uses the debug key: fine on a phone with no Breathe Free
on it, but it won't install over a release-signed build.

Before publishing an APK, check its certificate:

```bash
apksigner verify --print-certs app-release.apk | grep 'SHA-256 digest'
# ...certificate SHA-256 digest: 70adf95509f77edc47a81b0b8305955f784d87647f81bdc73f00078d40e632ae
```

### Screenshots without a device

```bash
./gradlew testDebugUnitTest -Pscreenshots --tests '*ScreenshotTest*'
```

renders the real screens at chosen moments of a session (Robolectric) into
`app/build/screenshots/`.

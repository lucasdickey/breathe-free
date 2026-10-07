# Promo videos

Two 30-second ads, one for the Mac app and one for the Android app, made from the apps
themselves: every frame is drawn by the app's own screens at a set moment, and the sound
is the app's own synth, so what you see and hear is what the app does.

`script.json` is the shared timeline: the opening sweep of the sky from morning to
night, when session length is opened, a count picked and Begin pressed, and how session
time lines up with video time (session time = video time - `lagSeconds`), so the breathing
runs at its true pace and every bell lands on its frame.

1. **Android frames and sound** (here, no device needed):

   ```bash
   cd android-app
   ./gradlew testDebugUnitTest -Ppromo --tests '*PromoTest*' --tests '*PromoAudioTest*'
   # frames: app/build/promo/android, sound: app/build/promo/audio
   ```

2. **Mac frames**: the "Promo footage" workflow renders them on a Mac runner
   (`macos-app/Promo/Promo.swift`) and attaches them to the run as
   `BreatheFree-macOS-promo-frames`.

3. **The edit**: `compose.py` puts the frames in a phone or a Mac window on a soft sky,
   adds the taps or the pointer, the captions and the end card, mixes the sound and encodes
   1920x1080, 30 fps H.264 with AAC:

   ```bash
   python3 promo/compose.py android <android frames> <audio folder> breathe-free-android.mp4
   python3 promo/compose.py mac <mac frames> <audio folder> breathe-free-mac.mp4
   ```

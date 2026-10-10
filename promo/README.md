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

   The test gives the app a phone's status bar and gesture bar, so it lays itself out
   below them as on a device; the edit draws what the system shows in them.

2. **Mac frames**: the "Promo footage" workflow renders them on a Mac runner
   (`macos-app/Promo/Promo.swift`) and attaches them to the run as
   `BreatheFree-macOS-promo-frames`. Session length's motion is a function of the media
   clock, so the renderer draws it frame by frame like the sky (`PickerMoment` tells the
   picker when it was opened and picked). The volume slider is an AppKit control, which the
   renderer leaves a yellow placeholder for, so the edit paints it in.

3. **The edit**: `compose.py` puts the frames in a phone or a Mac window on the app's own
   sky, pushes in on session length while it is used, adds the taps or the pointer, the
   captions and the end card, mixes the sound to YouTube's loudness (-14 LUFS) and encodes
   1920x1080, 30 fps H.264 with AAC:

   ```bash
   python3 promo/compose.py android <android frames> <audio folder> breathe-free-android.mp4
   python3 promo/compose.py mac <mac frames> <audio folder> breathe-free-mac.mp4
   ```

   Add `--stills=3.6,12.5` to draw just those moments as pictures beside the output, to
   check the look in seconds before a full encode.

## The 10-second time-of-day spot

`sun.json` is a shorter timeline for an update: the session is already breathing while the
clock sweeps from 5:54 in the morning to past midnight, so the sky and the light on the orb go
round a whole day in about eight seconds. `sun.py` edits it: the Mac window and the phone side
by side on their sky, a clock and a sun dial following the sweep (the dial's sun takes the
same path as the light on the orb), two captions and an end card, over the app's own sound.

```bash
cd android-app
./gradlew testDebugUnitTest -Ppromo -PpromoScript=sun.json --tests '*ui.PromoTest*' --tests '*PromoAudioTest*'
# Mac frames: run the "Promo footage" workflow by hand, with script sun.json
python3 promo/sun.py <mac frames> android-app/app/build/promo/android-sun \
  android-app/app/build/promo/audio breathe-free-sun.mp4
```

`--stills=` works here too.

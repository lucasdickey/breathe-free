# The voice

Lucas's own voice says each change aloud when "Speak each change" is on: "Breathe in",
"Hold" (for both holds) and "Breathe out". It is the one recording in the sound; everything
else is generated as it plays (see the top-level README).

## The clips

`cut/` holds the three takes as cut and cleaned, 48 kHz mono 16-bit, each at -20 LUFS, and
`masters/` the same takes with the stop that ends "Hold" and "Breathe out" rounded off (step 4
below). The apps carry the masters as AAC at 64 kbit/s
(`ffmpeg -i <master> -c:a aac -b:a 64k -movflags +faststart <clip>.m4a`), about 9 KB each:

| Clip | Length | Lead | In the apps |
|------|--------|------|-------------|
| Breathe in | 1.03 s | 164 ms | `android-app/.../res/raw/voice_breathe_in.m4a`, `macos-app/BreatheFree/Voice/breathe-in.m4a` |
| Hold | 0.85 s | 167 ms | `voice_hold.m4a`, `hold.m4a` |
| Breathe out | 0.91 s | 29 ms | `voice_breathe_out.m4a`, `breathe-out.m4a` |

The lead is how long after a clip's first sound (its first sample at 0.002, -54 dBFS) its
main vowel comes (the first 10 ms within 8 dB of its loudest). The synth starts each clip
that long before its change, so the vowel lands on the change with the bell. A decoder may
put silence before a clip; the apps trim each decoded clip to its first sound, so the lead
holds whatever the decoder does. Encoding and decoding were checked to move it by under
0.1 ms.

## How they were made

From a 22-second phone recording (a voice memo, AAC, 48 kHz) of nine takes: four of
"Breathe in", two of "Hold", three of "Breathe out". The first take of each was chosen.

1. `tools/voice_transcribe.py`: faster-whisper (`small.en`, word timestamps) finds which
   words are where.
2. `tools/voice_clip.py`: each take is cut at the sound's own start and end, found from its
   level near Whisper's span. The cut reaches back for the soft "B" or the breathy "H" of
   "Hold" (within 35 dB of the take's peak, at most 0.3 s, so a breath before the word stays
   out) and forward for the fading end and the "t" of "out" (until 80 ms within 6 dB of the
   room's noise). 8 ms fade in, 40 ms fade out.
3. `tools/voice_process.py`: a gentle low cut below 70 Hz (most of the room's noise was
   rumble below it), then each take brought to -20 LUFS. The chosen takes, as they come
   out of this step, are `cut/`.
4. `tools/voice_round_stops.py`: "Hold" ends in a "d" and "Breathe out" in a "t", and each
   was released as a sharp, bright burst after a moment of silence, which popped (the "d"
   most, in the quiet hold after breathing out). Each stop is kept but rounded off: from
   10 ms before its release the take is 12 dB quieter, its treble is softened above 3 kHz,
   and it swells in over 30 ms instead of starting at once. In the session's own mix, in
   the treble where a click is heard, the "d" went from 32 dB above what plays under it to
   4 dB in the first hold (from 49 to 20 in the second, where almost nothing plays up
   there), and the "t" from 8 dB to 3 dB; each now swells in rather than jumping. Everything before the closure is untouched, so the leads hold.
   (`voice_round_stops.py cut/hold.wav masters/hold.wav`, the same for `breathe-out.wav`;
   "Breathe in" ends without a stop, so its master is its cut take.)
5. `tools/voice_preview.py`: mixes the clips over a rendered session, each on its change,
   to listen to before changing the apps. `VoicePreviewTest` in the Android app does the
   same through the app's own synth.

The scripts read their input and output as arguments; each says how to run it at the top. A new recording goes through the same steps, with its own leads measured as
above.

## How loud

Prompts come at -20 LUFS. With the voice on, the synth plays the pad, air and bells 5 dB
quieter for the whole session, and puts the voice over them at the balance of the preview
that was chosen by ear; together they stay clear of the synth's limiter (it touches about
0.2% of samples, at the voice's loudest moments).

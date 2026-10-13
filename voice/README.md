# The voice

Lucas's own voice says each change aloud when "Speak each change" is on: "Breathe in",
"Hold" (for both holds) and "Breathe out". It is the one recording in the sound; everything
else is generated as it plays (see the top-level README).

## The clips

`masters/` holds the three clips as cut and cleaned, 48 kHz mono 16-bit, each at -20 LUFS.
The apps carry them as AAC at 64 kbit/s (`ffmpeg -c:a aac -b:a 64k`), about 9 KB each:

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
   rumble below it), then each take brought to -20 LUFS.
4. `tools/voice_soft_t.py`: the "t" at the end of "Breathe out" was released as a sharp
   spike after a moment of silence, which popped. From just before it the take is 14 dB
   quieter, and the spike's edge is a 4 ms ramp, so a faint "ts" is left.
5. `tools/voice_preview.py`: mixes the clips over a rendered session, each on its change,
   to listen to before changing the apps. `VoicePreviewTest` in the Android app does the
   same through the app's own synth.

The scripts read their input as arguments and write next to it; each says how to run it
at the top. A new recording goes through the same steps, with its own leads measured as
above.

## How loud

Prompts come at -20 LUFS. With the voice on, the synth plays the pad, air and bells 5 dB
quieter for the whole session, and puts the voice over them at the balance of the preview
that was chosen by ear; together they stay clear of the synth's limiter (it touches about
0.2% of samples, at the voice's loudest moments).

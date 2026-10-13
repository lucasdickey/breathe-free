"""End a word at its final stop's closure: "Hold" before its "d" is released, "Breathe out"
before its "t" is.

A word that ends in a stop ends with a moment of near-silence (the tongue closed) and then
a release: a burst that rises in about a millisecond and is brighter than anything before
it. Coming alone after the silence, with nothing after it, it pops, however much it is
turned down or rounded off. Speaking softly, people often don't release a final stop at all,
and the word still ends in it: the vowel stops into the closure. So the take is kept up to
3 ms before the release and fades out over the 15 ms before that, inside the closure's
near-silence, and the release is left out.

Prints where the release was, how quiet the closure is where the fade falls (against the
take's loudest 10 ms), and the new length.

usage: python3 -I voice_end_stops.py <take.wav> <out.wav>
"""
import sys
import wave

import numpy as np

SR = 48000
BEFORE_RELEASE = 0.003
FADE = 0.015


def read(path):
    with wave.open(path) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768


def write(path, y):
    with wave.open(path, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(SR)
        # The same scale as read() uses, so the part kept comes out bit for bit.
        o.writeframes(np.clip((y * 32768).round(), -32768, 32767).astype("<i2").tobytes())


take, out = sys.argv[1:3]
y = read(take)
hop, win = SR // 200, SR // 100
n = (len(y) - win) // hop
db = np.array([20 * np.log10(np.sqrt(np.mean(y[i * hop: i * hop + win] ** 2)) + 1e-9) for i in range(n)])
peak = db.max()

# The release: after the last 10 ms within 15 dB of the loudest, the first sample that jumps
# to five times the level of the 20 ms before it and to at least 2% of the take's tallest.
last_loud = max(i for i in range(n) if db[i] > peak - 15)
look, top = SR // 50, np.abs(y).max()
onset = next((k for k in range(last_loud * hop + win, len(y))
              if abs(y[k]) > 5 * (np.sqrt(np.mean(y[k - look: k] ** 2)) + 1e-6) and abs(y[k]) > 0.02 * top), None)
if onset is None:
    sys.exit(f"{take}: no stop at the end (no sudden release after the vowel); nothing to end")

stop = onset - int(BEFORE_RELEASE * SR)
fade = int(FADE * SR)
z = y[:stop].copy()
z[-fade:] *= 0.5 + 0.5 * np.cos(np.linspace(0, np.pi, fade))
under = 20 * np.log10(np.sqrt(np.mean(y[stop - fade: stop] ** 2)) + 1e-9) - peak
print(f"{take.rsplit('/', 1)[-1]}: release at {onset / SR:.4f} s; ends at {stop / SR:.4f} s, the fade in the closure "
      f"{-under:.0f} dB under the loudest 10 ms; {len(y) / SR:.3f} s -> {len(z) / SR:.3f} s")
write(out, z)

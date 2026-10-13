"""Round off the stop at the end of a word: the "d" of Hold, the "t" of Breathe out.

A word that ends in a stop ends with a moment of near-silence (the tongue closed) and then
a release: a burst that rises in about a millisecond and is brighter than anything before
it. Coming alone after the silence, with nothing after it, it pops. Without taking the stop
away, three things round it off, from just before the release to the end of the clip:

- the top is softened: a gentle treble cut (a low-pass filter, run forwards and then
  backwards so it doesn't move anything in time), so the burst's sharp edge goes;
- it swells in: from the release its level rises over --swell ms from --floor dB, instead
  of at once;
- it is quieter: --level dB under the take.

The take is untouched up to 10 ms before the release, in the closure's near-silence, and
crossfades from there. Prints, before and after, the release's loudest millisecond, the
biggest jump from one millisecond to the next as it starts (from 3 ms before the release to
6 ms after; both against the take's loudest 10 ms, so a jump of -20 dB is a step a tenth as
loud as the vowel), and its treble (2-10 kHz) against the vowel's.

usage: python3 -I voice_round_stops.py <take.wav> <out.wav> [--level dB] [--cutoff Hz]
           [--swell ms] [--floor dB]
The defaults (-12 dB, from 3 kHz, a 30 ms swell from -40 dB) made both masters.
"""
import argparse
import sys
import wave

import numpy as np

SR = 48000

ap = argparse.ArgumentParser()
ap.add_argument("take")
ap.add_argument("out")
ap.add_argument("--level", type=float, default=-12.0)
ap.add_argument("--cutoff", type=float, default=3000.0)
ap.add_argument("--swell", type=float, default=30.0)
ap.add_argument("--floor", type=float, default=-40.0)
args = ap.parse_args()


def read(path):
    with wave.open(path) as w:
        assert w.getframerate() == SR and w.getnchannels() == 1 and w.getsampwidth() == 2, path
        return np.frombuffer(w.readframes(w.getnframes()), "<i2").astype(np.float64) / 32768


def write(path, y):
    with wave.open(path, "wb") as o:
        o.setnchannels(1); o.setsampwidth(2); o.setframerate(SR)
        # The same scale as read() uses, so the untouched part comes out bit for bit.
        o.writeframes(np.clip((y * 32768).round(), -32768, 32767).astype("<i2").tobytes())


def low_pass(x, fc):
    """Two-pole Butterworth low-pass (RBJ biquad), run forwards then backwards."""
    w0 = 2 * np.pi * fc / SR
    alpha = np.sin(w0) / (2 * np.sqrt(0.5))
    c = np.cos(w0)
    b = np.array([(1 - c) / 2, 1 - c, (1 - c) / 2]) / (1 + alpha)
    a1, a2 = -2 * c / (1 + alpha), (1 - alpha) / (1 + alpha)

    def run(v):
        out = np.zeros_like(v)
        x1 = x2 = y1 = y2 = 0.0
        for i, s in enumerate(v):
            o = b[0] * s + b[1] * x1 + b[2] * x2 - a1 * y1 - a2 * y2
            x2, x1, y2, y1 = x1, s, y1, o
            out[i] = o
        return out

    return run(run(x)[::-1])[::-1]


def raised(n):
    return 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, n))


def ms_levels(y, a, n, ref):
    """Level of each millisecond from sample a, as a fraction of ref (an RMS)."""
    w = SR // 1000
    return np.array([np.sqrt(np.mean(y[a + i * w: a + (i + 1) * w] ** 2)) / ref for i in range(n)])


def treble(seg):
    spec = np.abs(np.fft.rfft(seg * np.hanning(len(seg)), n=8192)) ** 2
    f = np.fft.rfftfreq(8192, 1 / SR)
    return 10 * np.log10(spec[(f >= 2000) & (f < 10000)].sum() + 1e-12)


def report(label, y, onset, ref, vi):
    lv = ms_levels(y, onset - 3 * SR // 1000, 40, ref)
    db = lambda v: 20 * np.log10(max(v, 1e-9))
    w = SR // 1000
    tr = treble(y[onset - w: onset + 15 * w]) - treble(y[vi - 8 * w: vi + 8 * w])
    print(f"  {label:6} loudest ms {db(lv.max()):6.1f} dB, biggest jump as it starts {db(np.diff(lv[:10]).max()):6.1f} dB, "
          f"treble {tr:+5.1f} dB against the vowel's")


y = read(args.take)
hop, win = SR // 200, SR // 100
n = (len(y) - win) // hop
db = np.array([20 * np.log10(np.sqrt(np.mean(y[i * hop: i * hop + win] ** 2)) + 1e-9) for i in range(n)])
peak = db.max()
vi = int(np.argmax(db)) * hop + win // 2

# The release: after the last 10 ms within 15 dB of the loudest, the first sample that jumps
# to five times the level of the 20 ms before it and to at least 2% of the take's tallest.
last_loud = max(i for i in range(n) if db[i] > peak - 15)
look, top = SR // 50, np.abs(y).max()
onset = next((k for k in range(last_loud * hop + win, len(y))
              if abs(y[k]) > 5 * (np.sqrt(np.mean(y[k - look: k] ** 2)) + 1e-6) and abs(y[k]) > 0.02 * top), None)
if onset is None:
    sys.exit(f"{args.take}: no stop at the end (no sudden release after the vowel); nothing to round off")

ms = SR // 1000
start = onset - 10 * ms                      # crossfade from the take, in the closure
mix = np.zeros_like(y)
mix[start: start + 8 * ms] = raised(8 * ms)
mix[start + 8 * ms:] = 1.0
# The rounded take's level: steady through the closure, dipping to the floor over the 4 ms
# before the release, then swelling back.
fl = 10 ** (args.floor / 20)
s0, sn = onset - ms, int(args.swell * ms)
swell = np.ones_like(y)
swell[s0 - 4 * ms: s0] = 1 - (1 - fl) * raised(4 * ms)
swell[s0: s0 + sn] = fl + (1 - fl) * raised(sn)
rounded = low_pass(y, args.cutoff) * swell * 10 ** (args.level / 20)
z = y * (1 - mix) + rounded * mix

print(f"{args.take.rsplit('/', 1)[-1]}: release at {onset / SR:.4f} s, {(len(y) - onset) / ms:.0f} ms before the end; "
      f"level {args.level:+.0f} dB, treble cut from {args.cutoff:.0f} Hz, swell {args.swell:.0f} ms from {args.floor:.0f} dB")
ref = 10 ** (peak / 20)
report("before", y, onset, ref, vi)
report("after", z, onset, ref, vi)
write(args.out, z)
